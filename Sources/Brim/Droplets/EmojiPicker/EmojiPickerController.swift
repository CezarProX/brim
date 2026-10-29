import AppKit
import SwiftUI

/// Floating emoji picker opened by a global shortcut. It does not take focus from the app you
/// are typing in, and inserts the chosen emoji there by pasting (the clipboard is restored).
@MainActor
final class EmojiPickerController: NSObject, NSWindowDelegate {
  static let shared = EmojiPickerController()
  private var panel: EmojiPanel?
  private var target: NSRunningApplication?
  private let hotkey = DropletHotkey()
  private let settings = AppSettings.shared

  /// Registers the shortcut when the picker is enabled; call again after settings change.
  func start() {
    hotkey.unregister()
    guard settings.emojiPickerEnabled else { return }
    hotkey.onPress = { [weak self] in self?.toggle() }
    if !hotkey.register(keyCode: settings.emojiHotkeyCode, modifiers: settings.emojiHotkeyModifiers) {
      IslandFlashCenter.shared.show("Emoji shortcut is taken", symbol: "face.smiling", tint: .orange)
    }
  }

  func toggle() {
    if panel != nil { close() } else { show() }
  }

  func show() {
    close()
    target = EmojiInserter.frontTarget()
    let model = EmojiPickerModel()
    model.onPick = { [weak self] character in self?.insert(character) }
    let host = NSHostingView(rootView: EmojiPickerView(model: model, onClose: { [weak self] in self?.close() }))
    let size = host.fittingSize
    let panel = EmojiPanel(
      contentRect: CGRect(origin: origin(for: size), size: size),
      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    panel.isReleasedWhenClosed = false
    panel.backgroundColor = .clear
    panel.isOpaque = false
    panel.hasShadow = true
    panel.level = .floating
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.delegate = self
    panel.contentView = host
    panel.makeKeyAndOrderFront(nil)
    self.panel = panel
  }

  func close() {
    guard let panel else { return }
    self.panel = nil
    panel.delegate = nil
    panel.orderOut(nil)
  }

  func windowDidResignKey(_ notification: Notification) { close() }

  private func origin(for size: CGSize) -> CGPoint {
    let pointer = NSEvent.mouseLocation
    let screen = NSScreen.screens.first { $0.frame.contains(pointer) } ?? NSScreen.main
    let bounds = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
    return CGPoint(
      x: min(max(pointer.x - size.width / 2, bounds.minX + 8), bounds.maxX - size.width - 8),
      y: min(max(pointer.y - size.height - 18, bounds.minY + 8), bounds.maxY - size.height - 8))
  }

  // MARK: Insert

  private func insert(_ character: String) {
    close()
    EmojiInserter.insert(character, into: target)
  }
}

/// Puts an emoji into the app the user was typing in: copies it, then pastes with Cmd+V and
/// restores the clipboard. Without Accessibility access it can only copy, and says so.
@MainActor
enum EmojiInserter {
  enum Outcome { case pasted, copiedOnly }

  /// The app to insert into: whatever is frontmost, unless that is Brim itself.
  static func frontTarget() -> NSRunningApplication? {
    NSWorkspace.shared.frontmostApplication.flatMap {
      $0.bundleIdentifier == Bundle.main.bundleIdentifier ? nil : $0
    }
  }

  @discardableResult
  static func insert(_ character: String, into target: NSRunningApplication?, trusted: Bool = AXIsProcessTrusted()) -> Outcome {
    let pasteboard = NSPasteboard.general
    let saved = EmojiPasteboard.snapshot(pasteboard)
    pasteboard.clearContents()
    pasteboard.setString(character, forType: .string)
    guard trusted else {
      IslandFlashCenter.shared.show(
        "Copied \(character)", symbol: "doc.on.clipboard", tint: .orange, detail: "Allow Accessibility to paste automatically")
      return .copiedOnly
    }
    target?.activate()
    Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(120))
      postPaste()
      try? await Task.sleep(for: .milliseconds(450))
      EmojiPasteboard.restore(saved, to: pasteboard)
    }
    return .pasted
  }

  private static func postPaste() {
    let source = CGEventSource(stateID: .combinedSessionState)
    for down in [true, false] {
      let event = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: down)  // V
      event?.flags = .maskCommand
      event?.post(tap: .cghidEventTap)
    }
  }
}

/// Saves and restores every item on the pasteboard around a paste.
enum EmojiPasteboard {
  struct Snapshot { let items: [[NSPasteboard.PasteboardType: Data]] }

  static func snapshot(_ pasteboard: NSPasteboard) -> Snapshot {
    Snapshot(
      items: (pasteboard.pasteboardItems ?? []).map { item in
        Dictionary(uniqueKeysWithValues: item.types.compactMap { type in item.data(forType: type).map { (type, $0) } })
      })
  }

  static func restore(_ snapshot: Snapshot, to pasteboard: NSPasteboard) {
    pasteboard.clearContents()
    let restored = snapshot.items.map { entry -> NSPasteboardItem in
      let item = NSPasteboardItem()
      entry.forEach { item.setData($1, forType: $0) }
      return item
    }
    if !restored.isEmpty { pasteboard.writeObjects(restored) }
  }
}

private final class EmojiPanel: NSPanel {
  override var canBecomeKey: Bool { true }
  override func cancelOperation(_ sender: Any?) { orderOut(nil) }
}
