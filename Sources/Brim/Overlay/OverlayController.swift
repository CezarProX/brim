// OverlayController.swift
// Brim
//
// Presents one borderless, always-on-top window per display for the
// Lightshot-style capture flow: dim everything, let the user drag out a
// selection, then host the annotation editor (canvas + toolbar + action
// bar) floating around that selection until the user picks a final action.
//
// State is intentionally centralized here rather than split across the
// per-screen views: a selection is confined to a single screen at a time
// (the screen the drag started on — an accepted simplification, see
// `ARCHITECTURE.md`), so one controller owning `activeScreen` +
// `selectionRect` is simpler than keeping N per-screen view controllers in
// sync.
//
// File layout (kept small & focused per project convention):
//   OverlayController.swift              — state + window/session lifecycle
//   OverlayController+Mouse.swift        — drag-to-select / move / resize
//   OverlayController+Session.swift      — editor session + hosted-view lifecycle
//   OverlayController+Keyboard.swift     — Esc/Return/Cmd shortcuts
//   OverlayController+Compositing.swift  — crop + render + fire onAction
//   OverlayWindow.swift                  — per-screen NSWindow
//   SelectionOverlayView.swift           — per-screen NSView (draw + mouse)
//   ResizeHandle.swift                   — 8-handle geometry + cursors
//   ToolbarPositioner.swift              — floating toolbar/action-bar layout
//   RoundedContainerView.swift           — subtle rounded chrome background
//   ImageCropper.swift                   — points-rect -> cropped NSImage

import AppKit

/// The action the user chose to perform on the finished (annotated,
/// cropped) capture.
enum OverlayAction {
    case copy
    case save
    case upload
    case share
    case print
    case confirm
}

@MainActor final class OverlayController {

    static let shared = OverlayController()

    /// Fired once the user picks a final action (via the action bar or a
    /// keyboard shortcut). The image is the fully composited result:
    /// cropped to the selection, with annotations flattened in.
    var onAction: ((OverlayAction, NSImage) -> Void)?

    /// Fired when the user cancels the whole capture (Esc, or the action
    /// bar's close button). Mirrors `OverlayController`'s existing contract
    /// with `CaptureCoordinator`: this controller does not tear itself down
    /// on cancel — the owner is expected to call `dismiss()`.
    var onCancelled: (() -> Void)?
    private var escapeMonitor: Any?

    var windows: [NSScreen: OverlayWindow] = [:]
    var views: [NSScreen: SelectionOverlayView] = [:]
    var frozenImages: [NSScreen: NSImage] = [:]

    /// The screen currently hosting the single, cross-screen active
    /// selection. `nil` when no selection has been started yet.
    var activeScreen: NSScreen?

    /// The committed selection rect, in `activeScreen`'s window-local
    /// coordinates. `nil` while dragging out a brand-new selection (that
    /// in-progress rect lives on the view as `liveDragRect` instead) or
    /// before any selection exists.
    var selectionRect: CGRect?

    enum DragMode {
        case none
        case creating(startPoint: CGPoint)
        case moving(startPoint: CGPoint, startRect: CGRect)
        case resizing(handle: ResizeHandle, startPoint: CGPoint, startRect: CGRect)
    }
    var dragMode: DragMode = .none

    /// The editing session for the current selection, and the views it's
    /// hosted in. All four are created together in `commitSelection(on:)`
    /// and torn down together in `teardownEditingHost()`.
    var session: EditorSession?
    var canvasView: AnnotationCanvasView?
    var toolbarContainer: RoundedContainerView?
    var actionBarContainer: RoundedContainerView?

    private init() {}

    /// Presents one overlay window per screen. `frozenImages` maps each
    /// screen to a points-sized `NSImage` backed by retina pixels; a screen
    /// missing from the map (or an empty dictionary altogether) falls back
    /// to dimming-only degraded mode for that screen.
    func begin(screens: [NSScreen], frozenImages: [NSScreen: NSImage]) {
        dismiss()
        self.frozenImages = frozenImages

        for screen in screens {
            let window = makeWindow(for: screen)
            windows[screen] = window
            window.orderFrontRegardless()
        }

        // A menu-bar app is usually in the background when its hotkey fires. Without activating it,
        // the overlay never becomes key: drags and Esc go to the app underneath and the frozen screen
        // looks hung.
        NSApp.activate(ignoringOtherApps: true)
        InputTrace.note("overlay.begin screens=\(screens.count) active=\(NSApp.isActive)")
        let keyScreen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? screens.first
        if let keyScreen, let keyWindow = windows[keyScreen] {
            keyWindow.makeKeyAndOrderFront(nil)
        }
        installEscapeHatch()
    }

    /// Esc always cancels a capture, even if another app kept key focus.
    private func installEscapeHatch() {
        removeEscapeHatch()
        escapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return }
            MainActor.assumeIsolated { self?.cancelAll() }
        }
    }

    private func removeEscapeHatch() {
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        escapeMonitor = nil
    }

    /// Tears down every overlay window and all selection/editing state.
    func dismiss() {
        removeEscapeHatch()
        teardownEditingHost()
        session = nil
        selectionRect = nil
        activeScreen = nil
        dragMode = .none
        windows.values.forEach { $0.orderOut(nil) }
        windows.removeAll()
        views.removeAll()
        frozenImages.removeAll()
    }

    private func makeWindow(for screen: NSScreen) -> OverlayWindow {
        let window = OverlayWindow(screen: screen)

        let view = SelectionOverlayView(frame: CGRect(origin: .zero, size: screen.frame.size))
        view.autoresizingMask = [.width, .height]
        view.frozenImage = frozenImages[screen]
        view.onMouseDown = { [weak self] point in self?.handleMouseDown(screen: screen, point: point) }
        view.onMouseDragged = { [weak self] point in self?.handleMouseDragged(screen: screen, point: point) }
        view.onMouseUp = { [weak self] point in self?.handleMouseUp(screen: screen, point: point) }

        window.contentView = view
        window.onPerformKeyEquivalent = { [weak self] event in self?.handleKeyEvent(event) ?? false }

        views[screen] = view
        return window
    }

    func windowFor(_ screen: NSScreen) -> OverlayWindow? {
        windows[screen]
    }

    /// Temporarily orders the overlay windows out (or back in) WITHOUT
    /// tearing down the current selection/editing state — unlike `dismiss()`,
    /// `session`, `selectionRect`, `activeScreen`, and `frozenImages` are all
    /// left untouched. Used when an action needs other system UI (e.g. an
    /// `NSSavePanel`) to be visible on top while keeping the capture session
    /// alive (`AppSettings.closeAfterSave == false`).
    func setHidden(_ hidden: Bool) {
        if hidden {
            windows.values.forEach { $0.orderOut(nil) }
        } else {
            windows.values.forEach { $0.orderFrontRegardless() }
        }
    }

    /// Brings every per-screen view's drawn state back in sync after
    /// `activeScreen`/`selectionRect` change.
    func refreshAllViewStates() {
        for (screen, view) in views {
            view.isActiveScreen = (screen == activeScreen)
            if screen != activeScreen {
                view.selectionRect = nil
                view.liveDragRect = nil
            }
        }
    }

    /// Cancels the whole capture. Does not tear down windows itself — the
    /// owner of `onCancelled` is expected to call `dismiss()`.
    func cancelAll() {
        onCancelled?()
    }
}
