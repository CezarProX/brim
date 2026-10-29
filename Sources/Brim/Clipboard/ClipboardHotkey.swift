// ClipboardHotkey.swift
// Brim
//
// Global ⌥⇧Space (Carbon RegisterEventHotKey, same pattern as HotkeyManager) that opens the
// clipboard library. Uses its own signature ("QSCB") and event handler so it can never
// collide with HotkeyManager's hotkeys (signature "QSHK", ids 1 and 2).

import Carbon.HIToolbox
import Foundation

final class ClipboardHotkey {
    static let shared = ClipboardHotkey()
    /// Called on the main thread when the shortcut fires.
    var onPress: (() -> Void)?

    fileprivate static let signature = OSType(0x51_53_43_42)  // "QSCB"
    fileprivate static let identifier: UInt32 = 1

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private init() {}

    var isRegistered: Bool { hotKeyRef != nil }

    func register() {
        guard hotKeyRef == nil else { return }
        let binding = AppSettings.shared.clipboardShortcut
        guard binding.isSet else { return }
        installHandlerIfNeeded()
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(binding.keyCode), UInt32(binding.modifiers), EventHotKeyID(signature: Self.signature, id: Self.identifier),
            GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else {
            NSLog("Brim: clipboard shortcut unavailable (status=%d)", status)
            return
        }
        hotKeyRef = ref
    }

    func unregister() {
        guard let ref = hotKeyRef else { return }
        UnregisterEventHotKey(ref)
        hotKeyRef = nil
    }

    fileprivate func fire() { DispatchQueue.main.async { [weak self] in self?.onPress?() } }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), clipboardHotKeyHandler, 1, &spec, nil, &handlerRef)
        if status != noErr { NSLog("Brim: failed to install clipboard hotkey handler (status=%d)", status) }
    }
}

private func clipboardHotKeyHandler(next: EventHandlerCallRef?, event: EventRef?,
                                    userData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let event else { return OSStatus(eventNotHandledErr) }
    var pressed = EventHotKeyID()
    let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                   nil, MemoryLayout<EventHotKeyID>.size, nil, &pressed)
    guard status == noErr else { return OSStatus(eventNotHandledErr) }
    guard pressed.signature == ClipboardHotkey.signature, pressed.id == ClipboardHotkey.identifier else {
        return OSStatus(eventNotHandledErr)
    }
    ClipboardHotkey.shared.fire()
    return noErr
}
