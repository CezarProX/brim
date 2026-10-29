// AnnotationCanvasView.swift
// Brim
//
// The live, editable annotation canvas. Non-flipped, transparent-background
// NSView that renders `session.document.annotations` via
// `AnnotationRenderer` and turns mouse input into new/updated annotations
// on `session`, dispatching by `session.currentTool`.
//
// Split across files to stay small:
//  - AnnotationCanvasView.swift            drawing + mouse dispatch
//  - AnnotationCanvasView+Drafting.swift    pen / line / arrow / rect / highlighter in-progress state
//  - AnnotationCanvasView+Selection.swift   selection-mode hit-testing, move, hitTest override
//  - AnnotationCanvasView+TextEditing.swift inline NSTextField overlay for the text tool
//  - AnnotationCanvasView+Crop.swift        crop rubber-band and the dimmed crop overlay

import AppKit

@MainActor
final class AnnotationCanvasView: NSView {

    let session: EditorSession

    // Freehand pen stroke in progress (nil tool-state: see +Drafting.swift).
    var draftPenPoints: [CGPoint] = []

    // Rubber-band draft for line / arrow / rectangle / ellipse / blur / ... .
    var draftStart: CGPoint?
    var draftCurrent: CGPoint?

    // Crop rubber-band in progress (see +Crop.swift).
    var cropDraft: CGRect?

    // Selection-mode drag state.
    var selectionDragOriginal: Annotation?
    var selectionDragStart: CGPoint?
    var selectionDragOffset: CGSize = .zero

    // Resize-handle drag state (see +Handles.swift).
    var handleDragOriginal: Annotation?
    var activeHandle: AnnotationHandle?
    var handleDragPreview: Annotation?
    var handleDragOriginalTextSize: CGSize = .zero

    // A click (no drag) on a text annotation re-opens it for editing.
    var pendingTextEditCandidate: Annotation?

    // Inline text editing state.
    var textField: NSTextField?
    var editingAnnotationID: UUID?

    init(session: EditorSession) {
        self.session = session
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        session.addObserver { [weak self] in self?.handleSessionChanged() }
        session.setTextEditingEndHandler { [weak self] in self?.commitTextEditing() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var isFlipped: Bool { false }
    override var acceptsFirstResponder: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // In selection mode, clicks that miss every annotation AND every
        // resize handle must not be swallowed by this view, so the overlay
        // behind it (owned by agent-overlay) can still see the click.
        if session.currentTool == nil, let superview {
            let localPoint = convert(point, from: superview)
            if hitTestAnnotation(at: localPoint) == nil, hitTestHandle(at: localPoint) == nil {
                return nil
            }
        }
        return super.hitTest(point)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let displayed = session.visibleAnnotations.map { annotation -> Annotation in
            if annotation.id == selectionDragOriginal?.id {
                return translated(annotation, by: selectionDragOffset)
            }
            if annotation.id == handleDragPreview?.id, let preview = handleDragPreview {
                return preview
            }
            return annotation
        }
        let context = session.renderContext(canvasBounds: bounds)
        AnnotationRenderer.drawAll(displayed + draftAnnotations(), context: context)

        drawSelectionOutline()
        drawCropOverlay()
    }

    // MARK: - Mouse dispatch
    //
    // Priority order, regardless of the active tool:
    //  1. a resize handle of the selected annotation -> resize drag,
    //  2. an existing annotation under the cursor -> select + move drag
    //     (a click without movement on a text annotation re-opens editing),
    //  3. empty space -> the active tool draws (or deselects in
    //     selection mode).
    // Drawing a new shape therefore always starts on empty canvas.

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)

        if session.currentTool == .crop {
            if editingAnnotationID != nil { commitTextEditing() }
            beginCropDraft(at: point)
            return
        }

        if let (annotation, handle) = hitTestHandle(at: point) {
            if editingAnnotationID != nil { commitTextEditing() }
            beginHandleDrag(annotation: annotation, handle: handle, at: point)
            return
        }

        if let hit = hitTestAnnotation(at: point) {
            if editingAnnotationID != nil { commitTextEditing() }
            pendingTextEditCandidate = hit.tool == .text ? hit : nil
            beginSelectionDrag(at: point)
            return
        }

        guard let tool = session.currentTool else {
            beginSelectionDrag(at: point) // deselects on empty space
            return
        }

        switch tool {
        case .pen, .highlighter:
            beginPenStroke(at: point)
        case .text:
            handleTextToolMouseDown(at: point)
        case .counter:
            placeCounter(at: point)
        case .crop:
            beginCropDraft(at: point)
        default:
            beginShapeDraft(at: point)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        if activeHandle != nil {
            continueHandleDrag(at: point)
            return
        }

        if cropDraft != nil {
            continueCropDraft(at: point)
            return
        }

        if selectionDragOriginal != nil || session.currentTool == nil {
            continueSelectionDrag(at: point)
            if hypot(selectionDragOffset.width, selectionDragOffset.height) > 3 {
                pendingTextEditCandidate = nil
            }
            return
        }

        guard let tool = session.currentTool else { return }
        switch tool {
        case .pen, .highlighter:
            continuePenStroke(at: point)
        case .text, .counter, .crop:
            break
        default:
            continueShapeDraft(at: point)
        }
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        if activeHandle != nil {
            endHandleDrag(at: point)
            return
        }

        if cropDraft != nil {
            endCropDraft(at: point)
            return
        }

        if selectionDragOriginal != nil || session.currentTool == nil {
            endSelectionDrag(at: point)
            if let candidate = pendingTextEditCandidate {
                pendingTextEditCandidate = nil
                beginEditingText(annotation: candidate)
            }
            return
        }

        guard let tool = session.currentTool else { return }
        switch tool {
        case .pen, .highlighter:
            commitPenStroke(tool: tool)
        case .text, .counter, .crop:
            break
        default:
            commitShapeDraft(tool: tool)
        }
    }

    override func keyDown(with event: NSEvent) {
        let deleteKeyCodes: Set<UInt16> = [51, 117] // Backspace, Forward Delete
        // Delete the selected annotation in ANY tool mode — unless an inline
        // text field is being edited (then the field owns the key).
        if editingAnnotationID == nil,
           session.selectedAnnotationID != nil,
           deleteKeyCodes.contains(event.keyCode) {
            session.deleteSelected()
        } else {
            super.keyDown(with: event)
        }
    }

    // MARK: - Shared helpers

    /// Returns a copy of `annotation` translated by `offset`, used both for
    /// the live drag preview and to commit the final moved position.
    func translated(_ annotation: Annotation, by offset: CGSize) -> Annotation {
        AnnotationGeometry.translated(annotation, by: offset)
    }

    private func handleSessionChanged() {
        // If the active tool changes away from text mid-edit, commit
        // whatever's currently in the inline field rather than losing it.
        if editingAnnotationID != nil, session.currentTool != .text {
            commitTextEditing()
        }
        needsDisplay = true
    }
}
