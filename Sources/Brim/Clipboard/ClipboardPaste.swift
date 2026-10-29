// ClipboardPaste.swift
// Brim
//
// "Paste on select": after the island closes, send ⌘V to the app that was frontmost
// before Brim's island took over. Needs Accessibility; without it the entry is
// simply copied.

import AppKit
import ApplicationServices
import Carbon.HIToolbox

@MainActor
final class ClipboardPaster {
    static let shared = ClipboardPaster()
    private var lastExternalApp: NSRunningApplication?
    private var observer: NSObjectProtocol?

    /// Starts remembering the last app other than Brim that was activated.
    func start() {
        guard observer == nil else { return }
        lastExternalApp = Self.external(NSWorkspace.shared.frontmostApplication)
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { if let app = Self.external(app) { self?.lastExternalApp = app } }
        }
    }

    func stop() {
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observer = nil
    }

    private static func external(_ app: NSRunningApplication?) -> NSRunningApplication? {
        guard let app, app.bundleIdentifier != Bundle.main.bundleIdentifier else { return nil }
        return app
    }

    static var isAccessibilityTrusted: Bool { AXIsProcessTrusted() }

    /// Asks macOS to show the Accessibility prompt. Call only when the user turns Paste on select on.
    static func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// Sends ⌘V to the previously frontmost app after `delay`. Returns false (and does nothing)
    /// when Accessibility is not granted or no previous app is known.
    @discardableResult
    func pasteIntoPreviousApp(after delay: TimeInterval = 0.28) -> Bool {
        guard Self.isAccessibilityTrusted else { return false }
        let target = Self.external(NSWorkspace.shared.frontmostApplication) ?? lastExternalApp
        guard let target, !target.isTerminated else { return false }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            if !target.isActive { target.activate() }
            Self.sendCommandV()
        }
        return true
    }

    private static func sendCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: down)
            else { continue }
            event.flags = .maskCommand
            event.post(tap: .cghidEventTap)
        }
    }
}
