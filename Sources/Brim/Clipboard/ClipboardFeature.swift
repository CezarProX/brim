// ClipboardFeature.swift
// Brim
//
// Single entry point the app shell wires: `start()` at launch, `stop()` at termination.
// Owns the global shortcut, the previous-app tracker for Paste on select, and the hook
// that opens the island on the clipboard page.

import AppKit

@MainActor
final class ClipboardFeature {
    static let shared = ClipboardFeature()

    /// Opens the island on the clipboard page on the display under the pointer.
    /// Defaults to `NotchShelfController.presentClipboard()`.
    var openClipboard: () -> Void = { NotchShelfController.shared.presentClipboard() }

    private init() {}

    func start() {
        ClipboardPaster.shared.start()
        ClipboardHotkey.shared.onPress = { [weak self] in self?.openClipboard() }
        applySettings()
    }

    /// Re-reads the shortcut preference. Call after the setting changes (the settings UI does).
    func applySettings() {
        if AppSettings.shared.clipboardShortcutEnabled { ClipboardHotkey.shared.register() }
        else { ClipboardHotkey.shared.unregister() }
    }

    /// Call from `applicationWillTerminate`: honors "Clear history on quit".
    func stop() {
        ClipboardHotkey.shared.unregister()
        ClipboardPaster.shared.stop()
        ClipboardStore.shared.prepareForQuit()
    }
}
