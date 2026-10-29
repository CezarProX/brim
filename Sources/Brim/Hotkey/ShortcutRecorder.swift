// ShortcutRecorder.swift
// Brim
//
// An AppKit control that lets the user record a new global shortcut by
// clicking it and pressing a key combination. Captures the next keyDown
// (with modifiers), persists it to AppSettings, and re-registers the
// global hotkey. Wrapped for SwiftUI via ShortcutRecorderRepresentable.

import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Click-to-record control displaying the current global shortcut, e.g. "⌘⇧9".
final class ShortcutRecorderView: NSView {

    /// Fired after a new shortcut has been captured and persisted.
    var onShortcutChanged: (() -> Void)?

    private let label = NSTextField(labelWithString: "")
    private var isRecording = false {
        didSet { updateAppearance() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    private func setUp() {
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1

        label.alignment = .center
        label.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        let click = NSClickGestureRecognizer(target: self, action: #selector(handleClick))
        addGestureRecognizer(click)

        updateAppearance()
    }

    @objc private func handleClick() {
        isRecording = true
        window?.makeFirstResponder(self)
    }

    // MARK: - First responder / key capture

    override var acceptsFirstResponder: Bool { true }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        return super.resignFirstResponder()
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        if event.keyCode == kVK_Escape {
            isRecording = false
            window?.makeFirstResponder(nil)
            return
        }

        let carbonModifiers = Self.carbonModifiers(from: event.modifierFlags)
        guard carbonModifiers != 0 else {
            // Require at least one of Cmd/Ctrl/Option so the shortcut can't
            // collide with ordinary typing elsewhere in the system.
            NSSound.beep()
            return
        }

        AppSettings.shared.hotkeyKeyCode = Int(event.keyCode)
        AppSettings.shared.hotkeyModifiers = Int(carbonModifiers)
        HotkeyManager.shared.reregister()

        isRecording = false
        window?.makeFirstResponder(nil)
        onShortcutChanged?()
    }

    // MARK: - Appearance

    private func updateAppearance() {
        layer?.backgroundColor = (isRecording
            ? NSColor.controlAccentColor.withAlphaComponent(0.15)
            : NSColor.controlBackgroundColor).cgColor
        layer?.borderColor = (isRecording
            ? NSColor.controlAccentColor
            : NSColor.separatorColor).cgColor

        label.stringValue = isRecording
            ? "Type shortcut…"
            : Self.displayString(
                keyCode: AppSettings.shared.hotkeyKeyCode,
                modifiers: AppSettings.shared.hotkeyModifiers
            )
    }

    /// Re-reads AppSettings and refreshes the displayed shortcut string.
    /// Called by the SwiftUI wrapper whenever the shortcut may have changed
    /// elsewhere (e.g. "Reset to Default").
    func refresh() {
        guard !isRecording else { return }
        updateAppearance()
    }

    // MARK: - Modifier / key-code conversion helpers

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        return carbon
    }

    static func modifierSymbols(_ carbonModifiers: Int) -> String {
        let flags = UInt32(carbonModifiers)
        var symbols = ""
        if flags & UInt32(controlKey) != 0 { symbols += "⌃" }
        if flags & UInt32(optionKey) != 0 { symbols += "⌥" }
        if flags & UInt32(shiftKey) != 0 { symbols += "⇧" }
        if flags & UInt32(cmdKey) != 0 { symbols += "⌘" }
        return symbols
    }

    /// Human-readable string for a Carbon virtual key code, e.g. 25 -> "9",
    /// 36 -> "↩". Falls back to "?" for keys with no printable/known glyph.
    static func keyString(for keyCode: Int) -> String {
        if let special = specialKeyNames[keyCode] {
            return special
        }
        return characterKeyString(for: keyCode) ?? "?"
    }

    static func displayString(keyCode: Int, modifiers: Int) -> String {
        modifierSymbols(modifiers) + keyString(for: keyCode)
    }

    private static let specialKeyNames: [Int: String] = [
        kVK_Return: "↩",
        kVK_ANSI_KeypadEnter: "⌤",
        kVK_Tab: "⇥",
        kVK_Space: "Space",
        kVK_Delete: "⌫",
        kVK_ForwardDelete: "⌦",
        kVK_Escape: "⎋",
        kVK_LeftArrow: "←",
        kVK_RightArrow: "→",
        kVK_DownArrow: "↓",
        kVK_UpArrow: "↑",
        kVK_Home: "↖",
        kVK_End: "↘",
        kVK_PageUp: "⇞",
        kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4",
        kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8",
        kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]

    /// Translates a virtual key code to a printable character using the
    /// current keyboard layout (so e.g. non-US layouts still show the right
    /// glyph for the physical key the user pressed).
    private static func characterKeyString(for keyCode: Int) -> String? {
        guard let sourcePointer = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue() else {
            return nil
        }
        guard let layoutDataPointer = TISGetInputSourceProperty(
            sourcePointer,
            kTISPropertyUnicodeKeyLayoutData
        ) else {
            return nil
        }

        let layoutData = Unmanaged<CFData>.fromOpaque(layoutDataPointer).takeUnretainedValue() as Data
        return layoutData.withUnsafeBytes { rawBuffer -> String? in
            guard let keyLayoutPtr = rawBuffer.bindMemory(to: UCKeyboardLayout.self).baseAddress else {
                return nil
            }

            var deadKeyState: UInt32 = 0
            var chars = [UniChar](repeating: 0, count: 4)
            var length = 0

            let status = UCKeyTranslate(
                keyLayoutPtr,
                UInt16(keyCode),
                UInt16(kUCKeyActionDown),
                0,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                chars.count,
                &length,
                &chars
            )

            guard status == noErr, length > 0 else { return nil }
            return String(utf16CodeUnits: chars, count: length).uppercased()
        }
    }
}

// MARK: - SwiftUI bridge

/// SwiftUI wrapper around `ShortcutRecorderView` for use in the Preferences
/// window. `refreshToken` is bumped by the owning view whenever the
/// shortcut may have changed out-of-band (e.g. "Reset to Default").
struct ShortcutRecorderRepresentable: NSViewRepresentable {

    var refreshToken: Int
    var onShortcutChanged: () -> Void = {}

    func makeNSView(context: Context) -> ShortcutRecorderView {
        let view = ShortcutRecorderView()
        view.onShortcutChanged = onShortcutChanged
        return view
    }

    func updateNSView(_ nsView: ShortcutRecorderView, context: Context) {
        nsView.onShortcutChanged = onShortcutChanged
        nsView.refresh()
    }
}
