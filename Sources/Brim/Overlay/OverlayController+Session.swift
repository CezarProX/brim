// OverlayController+Session.swift
// Brim
//
// Lifecycle of the "editing host": the `EditorSession` plus the three
// floating views laid over/around the selection once one is committed
// (`AnnotationCanvasView`, `EditToolbarView`, `ActionBarView`).
//
// Locking contract: while no annotation tool is active, the selection
// itself owns mouse input (move/resize handles, click-outside-to-restart).
// Once the user picks a tool, the selection becomes locked — handles stop
// drawing/hit-testing (`SelectionOverlayView.isLocked`) and the annotation
// canvas view (exactly covering the selection rect, added as a frontmost
// subview) starts owning mouse input for drawing instead. See
// `OverlayController+Mouse.swift` for the "locked" checks on the selection
// side of this handoff.

import AppKit

extension OverlayController {

    /// Called once a drag ends with a valid (>= 4x4pt) rect: creates the
    /// editing session and hosts its views around the selection.
    func commitSelection(on screen: NSScreen) {
        guard let window = windowFor(screen), let rect = selectionRect, let contentView = window.contentView else {
            return
        }

        let newSession = EditorSession()
        newSession.onChanged = { [weak self] in self?.handleSessionChanged() }
        session = newSession

        let canvas = AnnotationCanvasView(session: newSession)
        canvas.frame = rect
        // Hidden until a tool is picked: while no tool is active the
        // selection itself owns mouse input (move/resize).
        canvas.isHidden = true
        contentView.addSubview(canvas)
        canvasView = canvas

        let toolbar = EditToolbarView(session: newSession)
        toolbar.onLayoutChanged = { [weak self] in self?.repositionHostedViews() }
        let toolbarBox = RoundedContainerView(hosting: toolbar)
        contentView.addSubview(toolbarBox)
        toolbarContainer = toolbarBox

        let callbacks = ActionBarCallbacks(
            upload: { [weak self] in self?.performAction(.upload) },
            share: { [weak self] in self?.performAction(.share) },
            print: { [weak self] in self?.performAction(.print) },
            copy: { [weak self] in self?.performAction(.copy) },
            save: { [weak self] in self?.performAction(.save) },
            close: { [weak self] in self?.cancelAll() }
        )
        let actionBar = ActionBarView(callbacks: callbacks)
        let actionBarBox = RoundedContainerView(hosting: actionBar)
        contentView.addSubview(actionBarBox)
        actionBarContainer = actionBarBox

        refreshAllViewStates()
        repositionHostedViews()
    }

    /// Repositions the canvas (exactly over the selection) and the
    /// floating toolbar/action-bar (around it). Called after every
    /// move/resize of the selection.
    func repositionHostedViews() {
        guard let screen = activeScreen, let rect = selectionRect else { return }

        canvasView?.frame = rect

        guard let toolbarBox = toolbarContainer, let actionBarBox = actionBarContainer else { return }
        let screenBounds = CGRect(origin: .zero, size: screen.frame.size)
        let layout = ToolbarPositioner.layout(
            selection: rect,
            screenBounds: screenBounds,
            toolbarSize: toolbarBox.panelSize,
            actionBarSize: actionBarBox.panelSize
        )
        toolbarBox.frame = layout.toolbar
        actionBarBox.frame = layout.actionBar
    }

    /// Wired to `EditorSession.onChanged`: keeps the canvas
    /// visible/hit-testable and the selection's locked (handle-hiding)
    /// state in sync with whether a tool is currently active.
    func handleSessionChanged() {
        let locked = session?.currentTool != nil
        canvasView?.isHidden = !locked && (session?.document.annotations.isEmpty ?? true)
        if let screen = activeScreen {
            views[screen]?.isLocked = locked
        }
    }

    /// Discards the current selection, its editing session, and its hosted
    /// views. Used both when starting a fresh selection and when the whole
    /// capture is dismissed.
    func discardCurrentSelection() {
        teardownEditingHost()
        if let screen = activeScreen {
            views[screen]?.selectionRect = nil
            views[screen]?.liveDragRect = nil
            views[screen]?.isLocked = false
        }
        session = nil
        selectionRect = nil
        activeScreen = nil
    }

    func teardownEditingHost() {
        canvasView?.removeFromSuperview()
        canvasView = nil
        toolbarContainer?.removeFromSuperview()
        toolbarContainer = nil
        actionBarContainer?.removeFromSuperview()
        actionBarContainer = nil
    }
}
