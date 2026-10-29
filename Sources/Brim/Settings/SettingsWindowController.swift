// SettingsWindowController.swift
// Brim
//
// Preferences window controller. Hosts the SwiftUI preferences UI
// (SettingsRootView) inside a resizable, System Settings-style NSWindow, created
// lazily on first use and reused thereafter.

import AppKit
import SwiftUI

final class SettingsWindowController {

    static let shared = SettingsWindowController()

    private var window: NSWindow?

    private init() {}

    /// Shows the preferences window, creating it on first use, and brings
    /// Brim to the foreground so the window is visible even though the
    /// app normally runs as a menu-bar-only accessory app.
    func show() {
        if window == nil {
            window = Self.makeWindow(rootView: SettingsRootView())
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// Opens Settings on an exact place: the page, the widget or tool page inside Home & Widgets,
    /// and the row to scroll to and highlight. Use this wherever the app tells the user to change
    /// something in Settings.
    @MainActor func show(_ destination: SettingsDestination) {
        SettingsNavigator.shared.open(destination)
        show()
    }

    /// Shorthand for `show(SettingsDestination(pane, anchor: anchor))`.
    @MainActor func show(page pane: SettingsPane, anchor: String? = nil) {
        show(SettingsDestination(pane, anchor: anchor))
    }

    /// A System Settings-style window: the content runs under a transparent, unified title bar so
    /// the glass reaches the top edge, and the pane's title shows in the toolbar.
    /// - Parameter backdrop: render tests only — a wallpaper drawn inside the window for the glass.
    static func makeWindow(rootView: SettingsRootView, backdrop: NSImage? = nil) -> NSWindow {
        let controller = NSHostingController(rootView: rootView.environment(\.glassRenderBackdrop, backdrop))
        controller.sceneBridgingOptions = [.title, .toolbars]

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: SettingsWindowLayout.defaultSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = controller
        window.title = L10n.tr("Brim Settings")
        window.titlebarAppearsTransparent = true
        // Glass from edge to edge: the window is clear and `GlassWindowBackdrop`
        // frosts the desktop behind both the sidebar and the page.
        GlassWindowChrome.apply(to: window)
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        window.contentMinSize = SettingsWindowLayout.minimumSize
        window.setContentSize(SettingsWindowLayout.defaultSize)
        window.center()

        return window
    }
}
