import AppKit
import Carbon.HIToolbox

/// Global shortcut (default ⌃⌥M) that mutes or unmutes every microphone. It has its own Carbon registration and
/// signature so it can't disturb the screenshot or Ring shortcuts; a clash with another app leaves it unregistered.
final class MeetingHotkey {
  static let shared = MeetingHotkey()
  fileprivate static let hotKeyID = EventHotKeyID(signature: OSType(0x51_53_4D_54), id: 1)  // "QSMT"
  private var hotKeyRef: EventHotKeyRef?
  private var handlerRef: EventHandlerRef?
  private init() {}

  /// Registers if enabled in settings. Safe to call repeatedly. Returns whether the shortcut is active.
  @discardableResult
  func register(settings: AppSettings = .shared) -> Bool {
    unregister()
    guard settings.muteAllMicsHotkeyEnabled else { return false }
    installHandlerIfNeeded()
    var ref: EventHotKeyRef?
    let status = RegisterEventHotKey(
      UInt32(settings.muteAllMicsKeyCode), UInt32(settings.muteAllMicsModifiers), Self.hotKeyID,
      GetApplicationEventTarget(), 0, &ref)
    guard status == noErr, let ref else {
      NSLog("Brim: could not register the mute-microphones shortcut (status=%d)", status)
      return false
    }
    hotKeyRef = ref
    return true
  }

  func unregister() {
    if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
    hotKeyRef = nil
  }

  fileprivate func fire() {
    MainActor.assumeIsolated { MicrophoneMuteController.shared.toggle() }
  }

  private func installHandlerIfNeeded() {
    guard handlerRef == nil else { return }
    var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    let status = InstallEventHandler(GetApplicationEventTarget(), meetingHotKeyHandler, 1, &spec, nil, &handlerRef)
    if status != noErr { NSLog("Brim: could not install the mute shortcut handler (status=%d)", status) }
  }
}

private func meetingHotKeyHandler(
  nextHandler: EventHandlerCallRef?, event: EventRef?, userData: UnsafeMutableRawPointer?
) -> OSStatus {
  guard let event else { return OSStatus(eventNotHandledErr) }
  var pressed = EventHotKeyID()
  let status = GetEventParameter(
    event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
    MemoryLayout<EventHotKeyID>.size, nil, &pressed)
  guard status == noErr, pressed.signature == MeetingHotkey.hotKeyID.signature, pressed.id == MeetingHotkey.hotKeyID.id
  else { return OSStatus(eventNotHandledErr) }
  DispatchQueue.main.async { MeetingHotkey.shared.fire() }
  return noErr
}
