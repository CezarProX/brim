// DropletShortcut.swift
// Brim
//
// A persisted global shortcut plus one shared Carbon dispatcher for all droplets
// (signature "QSDR", one id per droplet) so they can never collide with the other hotkeys.

import AppKit
import Carbon.HIToolbox
import SwiftUI

/// A key code + Carbon modifier mask. `modifiers == 0` means "no shortcut".
struct DropletShortcut: Equatable, Sendable {
  var keyCode: Int
  var modifiers: Int

  static let none = DropletShortcut(keyCode: 0, modifiers: 0)
  var isSet: Bool { modifiers != 0 }
  var display: String {
    isSet ? ShortcutRecorderView.displayString(keyCode: keyCode, modifiers: modifiers) : "Not set"
  }

  /// Reads `<prefix>ShortcutKey` / `<prefix>ShortcutMods`, falling back to `fallback`.
  static func load(_ prefix: String, fallback: DropletShortcut, from defaults: UserDefaults) -> DropletShortcut {
    guard let key = defaults.object(forKey: prefix + "ShortcutKey") as? Int,
      let mods = defaults.object(forKey: prefix + "ShortcutMods") as? Int
    else { return fallback }
    return DropletShortcut(keyCode: key, modifiers: mods)
  }

  func save(_ prefix: String, to defaults: UserDefaults) {
    defaults.set(keyCode, forKey: prefix + "ShortcutKey")
    defaults.set(modifiers, forKey: prefix + "ShortcutMods")
  }
}

/// Which droplet owns a hotkey id.
enum DropletID: UInt32, CaseIterable, Sendable {
  case termiNotch = 1, teleprompter, textCapture, dropClip, showNotes, newNote
}

@MainActor
final class DropletHotkeyCenter {
  static let shared = DropletHotkeyCenter()
  fileprivate static let signature = OSType(0x51_53_44_52)  // "QSDR"

  private var refs: [UInt32: EventHotKeyRef] = [:]
  private var handlers: [UInt32: () -> Void] = [:]
  private var handlerRef: EventHandlerRef?
  private init() {}

  func isRegistered(_ id: DropletID) -> Bool { refs[id.rawValue] != nil }

  /// Registers (replacing any earlier registration for `id`). Returns false if macOS refused it.
  @discardableResult
  func register(_ id: DropletID, shortcut: DropletShortcut, handler: @escaping () -> Void) -> Bool {
    unregister(id)
    guard shortcut.isSet, installHandlerIfNeeded() else { return false }
    var ref: EventHotKeyRef?
    let status = RegisterEventHotKey(
      UInt32(shortcut.keyCode), UInt32(shortcut.modifiers),
      EventHotKeyID(signature: Self.signature, id: id.rawValue), GetApplicationEventTarget(), 0, &ref)
    guard status == noErr, let ref else {
      NSLog("Brim: droplet shortcut %d unavailable (status=%d)", id.rawValue, status)
      return false
    }
    refs[id.rawValue] = ref
    handlers[id.rawValue] = handler
    return true
  }

  func unregister(_ id: DropletID) {
    if let ref = refs.removeValue(forKey: id.rawValue) { UnregisterEventHotKey(ref) }
    handlers[id.rawValue] = nil
  }

  fileprivate func fire(_ rawID: UInt32) { handlers[rawID]?() }

  private func installHandlerIfNeeded() -> Bool {
    if handlerRef != nil { return true }
    var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    let status = InstallEventHandler(GetApplicationEventTarget(), dropletHotKeyHandler, 1, &spec, nil, &handlerRef)
    if status != noErr { NSLog("Brim: droplet hotkey handler failed (status=%d)", status) }
    return status == noErr
  }
}

private func dropletHotKeyHandler(
  next: EventHandlerCallRef?, event: EventRef?, userData: UnsafeMutableRawPointer?
) -> OSStatus {
  guard let event else { return OSStatus(eventNotHandledErr) }
  var pressed = EventHotKeyID()
  let status = GetEventParameter(
    event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
    MemoryLayout<EventHotKeyID>.size, nil, &pressed)
  guard status == noErr, pressed.signature == DropletHotkeyCenter.signature else {
    return OSStatus(eventNotHandledErr)
  }
  let id = pressed.id
  DispatchQueue.main.async { MainActor.assumeIsolated { DropletHotkeyCenter.shared.fire(id) } }
  return noErr
}

// MARK: - Recorder control

/// Click, then press a combination (needs ⌘, ⌃ or ⌥). Escape cancels; the ✕ button clears.
struct DropletShortcutField: View {
  let title: String
  @Binding var shortcut: DropletShortcut

  var body: some View {
    HStack {
      Text(title)
      Spacer()
      RecorderRepresentable(shortcut: $shortcut).frame(width: 130, height: 24)
      Button {
        shortcut = .none
      } label: {
        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
      }
      .buttonStyle(.plain).help("Remove shortcut").disabled(!shortcut.isSet)
    }
  }
}

struct RecorderRepresentable: NSViewRepresentable {
  @Binding var shortcut: DropletShortcut

  func makeNSView(context: Context) -> RecorderView {
    let view = RecorderView()
    view.onChange = { shortcut = $0 }
    return view
  }

  func updateNSView(_ view: RecorderView, context: Context) {
    view.onChange = { shortcut = $0 }
    view.current = shortcut
  }
}

final class RecorderView: NSView {
  var onChange: ((DropletShortcut) -> Void)?
  var current = DropletShortcut.none { didSet { refresh() } }
  private let label = NSTextField(labelWithString: "")
  private var recording = false { didSet { refresh() } }

  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
    layer?.cornerRadius = 6
    layer?.borderWidth = 1
    label.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
    label.translatesAutoresizingMaskIntoConstraints = false
    addSubview(label)
    NSLayoutConstraint.activate([
      label.centerXAnchor.constraint(equalTo: centerXAnchor), label.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])
    refresh()
  }

  @available(*, unavailable) required init?(coder: NSCoder) { nil }

  override var acceptsFirstResponder: Bool { true }
  override func mouseDown(with event: NSEvent) {
    recording = true
    window?.makeFirstResponder(self)
  }
  override func resignFirstResponder() -> Bool {
    recording = false
    return super.resignFirstResponder()
  }

  override func keyDown(with event: NSEvent) {
    guard recording else { return super.keyDown(with: event) }
    if event.keyCode == UInt16(kVK_Escape) {
      recording = false
      return
    }
    let mods = ShortcutRecorderView.carbonModifiers(from: event.modifierFlags)
    guard mods & UInt32(cmdKey | controlKey | optionKey) != 0 else { return NSSound.beep() }
    current = DropletShortcut(keyCode: Int(event.keyCode), modifiers: Int(mods))
    recording = false
    onChange?(current)
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    refresh()
  }

  private func refresh() {
    // Resolve the dynamic colors in this view's own appearance so light/dark switches repaint correctly.
    effectiveAppearance.performAsCurrentDrawingAppearance {
      layer?.backgroundColor = (recording ? NSColor.controlAccentColor.withAlphaComponent(0.15) : .controlBackgroundColor).cgColor
      layer?.borderColor = (recording ? NSColor.controlAccentColor : .separatorColor).cgColor
    }
    label.stringValue = recording ? "Type shortcut…" : current.display
  }
}
