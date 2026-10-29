import Carbon.HIToolbox
import Foundation

/// A global shortcut owned by a Droplet. Uses Carbon hot keys with its own signature so it
/// coexists with `HotkeyManager`; a clash with another app leaves it unregistered.
@MainActor
final class DropletHotkey {
  private static let signature = OSType(0x51_53_44_52)  // "QSDR"
  private static var nextID: UInt32 = 1
  private static var handlers: [UInt32: () -> Void] = [:]
  private static var handlerRef: EventHandlerRef?

  private var ref: EventHotKeyRef?
  private let id: UInt32
  var onPress: () -> Void {
    didSet { Self.handlers[id] = onPress }
  }

  init(onPress: @escaping () -> Void = {}) {
    id = Self.nextID
    Self.nextID += 1
    self.onPress = onPress
    Self.handlers[id] = onPress
  }

  /// Registers (or re-registers) the shortcut; returns false when the system refuses it.
  @discardableResult
  func register(keyCode: Int, modifiers: Int) -> Bool {
    unregister()
    guard modifiers != 0 else { return false }
    Self.installHandlerIfNeeded()
    var newRef: EventHotKeyRef?
    let status = RegisterEventHotKey(
      UInt32(keyCode), UInt32(modifiers), EventHotKeyID(signature: Self.signature, id: id),
      GetApplicationEventTarget(), 0, &newRef)
    guard status == noErr, let newRef else { return false }
    ref = newRef
    return true
  }

  func unregister() {
    if let ref { UnregisterEventHotKey(ref) }
    ref = nil
  }

  fileprivate static func fire(_ id: UInt32) { handlers[id]?() }

  private static func installHandlerIfNeeded() {
    guard handlerRef == nil else { return }
    var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(GetApplicationEventTarget(), dropletHotKeyHandler, 1, &type, nil, &handlerRef)
  }
}

private func dropletHotKeyHandler(
  _ next: EventHandlerCallRef?, _ event: EventRef?, _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
  guard let event else { return OSStatus(eventNotHandledErr) }
  var pressed = EventHotKeyID()
  let status = GetEventParameter(
    event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
    MemoryLayout<EventHotKeyID>.size, nil, &pressed)
  guard status == noErr, pressed.signature == OSType(0x51_53_44_52) else {
    return OSStatus(eventNotHandledErr)
  }
  let id = pressed.id
  DispatchQueue.main.async { MainActor.assumeIsolated { DropletHotkey.fire(id) } }
  return noErr
}
