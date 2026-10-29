import AppKit
import Carbon.HIToolbox

/// Global shortcut (default ⌥⌘N, editable): toggle the island on the display under the pointer.
/// Registered with its own signature so it never interferes with `HotkeyManager`'s hotkeys
/// (⌘⇧9 and ⌥⌘R); each Carbon handler passes on events that are not its own.
@MainActor
final class ShellHotkey {
    static let shared = ShellHotkey()
    var onToggle: (() -> Void)?

    nonisolated fileprivate static let signature = OSType(0x51_53_49_53) // "QSIS"
    nonisolated fileprivate static let identifier: UInt32 = 3
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    func register() {
        guard hotKeyRef == nil else { return }
        let binding = AppSettings.shared.islandToggleShortcut
        guard binding.isSet else { return }
        if handlerRef == nil {
            var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let status = InstallEventHandler(GetApplicationEventTarget(), shellHotKeyHandler, 1, &type, nil, &handlerRef)
            guard status == noErr else {
                NSLog("Brim: failed to install island shortcut handler (status=%d)", status)
                return
            }
        }
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(binding.keyCode), UInt32(binding.modifiers),
                                         EventHotKeyID(signature: Self.signature, id: Self.identifier),
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else {
            NSLog("Brim: failed to register the island shortcut (status=%d)", status)
            return
        }
        hotKeyRef = ref
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
        if let handlerRef { RemoveEventHandler(handlerRef) }
        handlerRef = nil
    }

    fileprivate func fire() { onToggle?() }
}

private func shellHotKeyHandler(next: EventHandlerCallRef?, event: EventRef?, userData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let event else { return OSStatus(eventNotHandledErr) }
    var pressed = EventHotKeyID()
    let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                   nil, MemoryLayout<EventHotKeyID>.size, nil, &pressed)
    guard status == noErr, pressed.signature == ShellHotkey.signature, pressed.id == ShellHotkey.identifier else {
        return OSStatus(eventNotHandledErr)
    }
    DispatchQueue.main.async { MainActor.assumeIsolated { ShellHotkey.shared.fire() } }
    return noErr
}
