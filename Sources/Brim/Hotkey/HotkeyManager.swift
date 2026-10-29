// HotkeyManager.swift
// Brim
//
// Owns registration of the global "Take Screenshot" hotkey (default
// Cmd+Shift+9, see AppSettings.hotkeyKeyCode / hotkeyModifiers).
//
// Implemented using the Carbon `RegisterEventHotKey` / `InstallEventHandler`
// APIs — still the standard way to register a system-wide hotkey from a
// non-sandboxed AppKit app with no external dependencies.

import AppKit
import Carbon.HIToolbox

/// Registers / unregisters the single global "Take Screenshot" hotkey and
/// forwards presses to `onHotkey` on the main thread.
///
/// Not marked `@MainActor`: `AppDelegate` calls `register()` / `unregister()`
/// synchronously from non-isolated lifecycle methods. In practice every
/// call happens on the main thread (app lifecycle + Carbon event delivery),
/// and the hotkey-pressed callback explicitly hops to the main thread before
/// touching `onHotkey`.
final class HotkeyManager {

    static let shared = HotkeyManager()

    /// Called on the main thread whenever the registered global hotkey fires.
    /// AppDelegate sets this to trigger `CaptureCoordinator.shared.startCapture()`.
    var onHotkey: (() -> Void)?

    /// Called on the main thread when the Ring shortcut (⌥⌘R) fires.
    var onRingHotkey: (() -> Void)?

    /// Unique identifier Brim uses to recognize its own hotkey events
    /// among any others delivered to the process ("QSHK" packed into an OSType).
    fileprivate static let hotKeyID = EventHotKeyID(
        signature: OSType(0x51_53_48_4B),
        id: 1
    )

    fileprivate static let ringHotKeyID = EventHotKeyID(signature: OSType(0x51_53_48_4B), id: 2)

    private var hotKeyRef: EventHotKeyRef?
    private var ringHotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    private init() {}

    /// Registers the global hotkey described by `AppSettings`. Safe to call
    /// more than once — a no-op if already registered.
    func register() {
        guard hotKeyRef == nil else { return }
        guard AppSettings.shared.hotkeyModifiers != 0 else { return }

        installEventHandlerIfNeeded()

        let keyCode = UInt32(AppSettings.shared.hotkeyKeyCode)
        let modifiers = UInt32(AppSettings.shared.hotkeyModifiers)

        var newRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            Self.hotKeyID,
            GetApplicationEventTarget(),
            0,
            &newRef
        )

        guard status == noErr, let registeredRef = newRef else {
            NSLog(
                "Brim: failed to register global hotkey (keyCode=%d modifiers=%d status=%d)",
                keyCode, modifiers, status
            )
            hotKeyRef = nil
            return
        }

        hotKeyRef = registeredRef
    }

    /// Unregisters the currently-active global hotkey, if any.
    func unregister() {
        guard let ref = hotKeyRef else { return }
        let status = UnregisterEventHotKey(ref)
        if status != noErr {
            NSLog("Brim: failed to unregister global hotkey (status=%d)", status)
        }
        hotKeyRef = nil
    }

    /// Registers the Ring shortcut (default ⌥⌘R, editable in Settings > Shortcuts). A clash with another
    /// app, or a cleared shortcut, simply leaves it unregistered.
    func registerRing() {
        guard ringHotKeyRef == nil else { return }
        let binding = AppSettings.shared.ringShortcut
        guard binding.isSet else { return }
        installEventHandlerIfNeeded()
        var newRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(binding.keyCode), UInt32(binding.modifiers), Self.ringHotKeyID,
            GetApplicationEventTarget(), 0, &newRef)
        guard status == noErr, let registeredRef = newRef else {
            NSLog("Brim: failed to register the Ring shortcut (status=%d)", status)
            return
        }
        ringHotKeyRef = registeredRef
    }

    func unregisterRing() {
        guard let ref = ringHotKeyRef else { return }
        UnregisterEventHotKey(ref)
        ringHotKeyRef = nil
    }

    /// Re-reads `AppSettings` and re-registers the hotkey. Called after the
    /// user picks a new shortcut in Preferences.
    func reregister() {
        unregister()
        register()
    }

    /// Re-reads the Ring shortcut after the user edits it.
    func reregisterRing() {
        unregisterRing()
        registerRing()
    }

    /// Invoked (on the main thread) once the free-function Carbon callback
    /// has confirmed the event is Brim's own hotkey.
    fileprivate func handleHotKeyPressed(id: UInt32) {
        if id == Self.ringHotKeyID.id { onRingHotkey?() } else { onHotkey?() }
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandlerRef == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            brimHotKeyEventHandler,
            1,
            &eventType,
            nil,
            &eventHandlerRef
        )

        if status != noErr {
            NSLog("Brim: failed to install hotkey event handler (status=%d)", status)
        }
    }
}

/// C-compatible Carbon event handler. Must be a non-capturing function (not
/// a closure over `self`) so it can be converted to the C function pointer
/// `InstallEventHandler` requires. Confirms the event is Brim's hotkey,
/// then hops to the main thread to notify `HotkeyManager`.
private func brimHotKeyEventHandler(
    nextHandler: EventHandlerCallRef?,
    event: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event else { return OSStatus(eventNotHandledErr) }

    var pressedID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &pressedID
    )

    guard status == noErr else { return status }

    guard pressedID.signature == HotkeyManager.hotKeyID.signature,
          pressedID.id == HotkeyManager.hotKeyID.id || pressedID.id == HotkeyManager.ringHotKeyID.id else {
        return OSStatus(eventNotHandledErr)
    }

    let id = pressedID.id
    DispatchQueue.main.async {
        HotkeyManager.shared.handleHotKeyPressed(id: id)
    }

    return noErr
}
