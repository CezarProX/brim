import AppKit
import SwiftUI
import Vision

/// Pure planning for slot actions, separated from the side effects so it can be tested.
enum RingActionPlan {
  /// `shortcuts run <name>` argument vector; nil when the name is empty.
  static func shortcutArguments(name: String) -> [String]? {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : ["run", trimmed]
  }

  /// A URL a slot may open: any scheme except local files and scripts, with a host or an app scheme.
  static func openableURL(_ text: String) -> URL? {
    var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    if !trimmed.contains(":") { trimmed = "https://" + trimmed }
    guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() else { return nil }
    let blocked: Set<String> = ["file", "javascript", "data", "vbscript"]
    return blocked.contains(scheme) ? nil : url
  }

  /// AppleScript that nudges output volume, clamped to 0...100.
  static func volumeScript(delta: Int) -> String {
    "set volume output volume (((output volume of (get volume settings)) + (\(delta))) as integer)"
  }
}

/// Performs ring actions. Every failure surfaces as an island flash instead of being swallowed.
@MainActor
enum RingActionRunner {
  static func run(_ slot: RingSlot) async {
    switch slot.kind {
    case .builtIn: await builtIn(RingBuiltIn(rawValue: slot.argument))
    case .media: await media(RingMedia(rawValue: slot.argument))
    case .toggle: await toggle(RingToggle(rawValue: slot.argument))
    case .openApp: openApp(slot.argument)
    case .openURL: openURL(slot.argument)
    case .shortcut: await runShortcut(slot.argument)
    case .keystroke: keystroke(slot.argument)
    }
  }

  private static func flash(_ title: String, _ symbol: String, _ tint: Color = .white) {
    IslandFlashCenter.shared.show(title, symbol: symbol, tint: tint)
  }

  private static func builtIn(_ action: RingBuiltIn?) async {
    switch action {
    case .capture: CaptureCoordinator.shared.startCapture()
    case .grabText:
      guard let text = await grabText() else { return }
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(text, forType: .string)
      flash("Text copied", "text.viewfinder", .teal)
    case .colorPicker:
      let sampled: NSColor? = await withCheckedContinuation { continuation in
        NSColorSampler().show { continuation.resume(returning: $0) }
      }
      guard let color = sampled, let hex = ClipboardEntry.hex(color) else { return }
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(hex, forType: .string)
      flash(hex, "circle.fill", Color(nsColor: color))
    case .voiceMemo: await VoiceRecorderModel.shared.toggleRecording()
    case .emojiPicker: EmojiPickerController.shared.toggle()
    case .clipboard: NotchShelfController.shared.presentClipboard()
    case .settings: SettingsWindowController.shared.show()
    case nil: flash("Unknown action", "questionmark.circle", .orange)
    }
  }

  private static func media(_ control: RingMedia?) async {
    let player = NowPlayingModel.shared
    switch control {
    case .playPause: player.playPause()
    case .next: player.next()
    case .previous: player.previous()
    case .volumeUp: await script(RingActionPlan.volumeScript(delta: 8))
    case .volumeDown: await script(RingActionPlan.volumeScript(delta: -8))
    case .mute: await script("set volume output muted (not (output muted of (get volume settings)))")
    case nil: flash("Unknown media control", "questionmark.circle", .orange)
    }
  }

  private static func toggle(_ toggle: RingToggle?) async {
    switch toggle {
    case .keepAwake:
      StayAwakeController.shared.toggle()
    case .darkMode:
      await script("tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode")
    case nil: flash("Unknown toggle", "questionmark.circle", .orange)
    }
  }

  private static func script(_ source: String) async {
    guard let result = await DropletProcess.run("/usr/bin/osascript", ["-e", source], timeout: 10),
      result.status == 0
    else { return flash("Couldn’t run that", "exclamationmark.triangle.fill", .orange) }
  }

  private static func openApp(_ path: String) {
    guard !path.isEmpty, FileManager.default.fileExists(atPath: path) else {
      return flash("App not found", "questionmark.app", .orange)
    }
    NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: .init())
  }

  private static func openURL(_ text: String) {
    guard let url = RingActionPlan.openableURL(text) else { return flash("Invalid link", "link", .orange) }
    NSWorkspace.shared.open(url)
  }

  private static func runShortcut(_ name: String) async {
    guard let arguments = RingActionPlan.shortcutArguments(name: name) else {
      return flash("Pick a Shortcut", "square.stack.3d.up", .orange)
    }
    flash(name, "square.stack.3d.up.fill", .pink)
    guard let result = await DropletProcess.run("/usr/bin/shortcuts", arguments, timeout: 120), result.status == 0
    else { return flash("Shortcut failed", "exclamationmark.triangle.fill", .red) }
  }

  private static func keystroke(_ argument: String) {
    guard let stroke = RingKeystroke(argument) else { return flash("Invalid shortcut", "command", .orange) }
    guard AXIsProcessTrusted() else {
      return flash("Allow Accessibility to send keys", "hand.raised.fill", .orange)
    }
    let flags = cgFlags(carbon: stroke.modifiers)
    let source = CGEventSource(stateID: .combinedSessionState)
    for down in [true, false] {
      let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(stroke.keyCode), keyDown: down)
      event?.flags = flags
      event?.post(tap: .cghidEventTap)
    }
  }

  static func cgFlags(carbon: Int) -> CGEventFlags {
    let mask = UInt32(truncatingIfNeeded: carbon)
    var flags: CGEventFlags = []
    if mask & UInt32(0x0100) != 0 { flags.insert(.maskCommand) }
    if mask & UInt32(0x0800) != 0 { flags.insert(.maskAlternate) }
    if mask & UInt32(0x1000) != 0 { flags.insert(.maskControl) }
    if mask & UInt32(0x0200) != 0 { flags.insert(.maskShift) }
    return flags
  }

  /// Lets the user drag out a region with the system tool, then reads its text on device.
  private static func grabText() async -> String? {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("brim-ocr-\(UUID().uuidString).png")
    defer { try? FileManager.default.removeItem(at: file) }
    guard let result = await DropletProcess.run("/usr/sbin/screencapture", ["-i", "-x", file.path], timeout: 300),
      result.status == 0, FileManager.default.fileExists(atPath: file.path),
      let image = NSImage(contentsOf: file),
      let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    else { return nil }
    let text = await Task.detached(priority: .userInitiated) { ClipboardOCR.recognize(cgImage) }.value
    if text == nil { flash("No text found", "text.viewfinder") }
    return text
  }
}
