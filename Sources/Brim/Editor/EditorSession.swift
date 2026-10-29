// EditorSession.swift
// Brim
//
// The editor's public API surface. `AnnotationCanvasView`, `EditToolbarView`
// and other feature agents (agent-overlay) drive annotation editing entirely
// through this class. It owns the `AnnotationDocument` (the frozen contract
// from `Core/Annotation.swift`) and coordinates undo/redo, tool/style state,
// and the single-editor-at-a-time text-editing handshake with the canvas.
//
// `onChanged` is the one public notification closure per the contract. The
// canvas view (and any other observer) registers internally via
// `addObserver(_:)` so multiple listeners can react to the same state
// changes without fighting over a single closure slot.

import AppKit

@MainActor
final class EditorSession {

    private(set) var document = AnnotationDocument()

    var currentTool: AnnotationTool? {
        didSet {
            guard oldValue?.rawValue != currentTool?.rawValue else { return }
            notifyChanged()
        }
    }

    var currentStyle: AnnotationStyle = AnnotationStyle() {
        didSet {
            applyStyleToSelection()
            notifyChanged()
        }
    }

    var onChanged: (() -> Void)?

    /// The annotation currently selected in selection mode (`currentTool ==
    /// nil`). Not part of the frozen public API required by agent-overlay,
    /// but exposed so `AnnotationCanvasView` (in this same module/directory)
    /// can drive click-to-select / drag-to-move behavior through the
    /// session rather than mutating the document directly.
    private(set) var selectedAnnotationID: UUID?

    private(set) var isEditingText: Bool = false

    /// The screenshot under the annotations and the canvas rect it covers.
    /// Set by hosts that have the pixels (the editor window) so blur,
    /// pixelate and the magnifier preview live; nil in the capture overlay.
    private(set) var sourceImage: CGImage?
    private(set) var sourceFrame: CGRect = .zero

    private var observers: [() -> Void] = []
    private var textEditingEndHandler: (() -> Void)?

    init() {}

    // MARK: - Public API (contract)

    func undo() {
        document.undo()
        selectedAnnotationID = nil
        notifyChanged()
    }

    func redo() {
        document.redo()
        selectedAnnotationID = nil
        notifyChanged()
    }

    func clearAnnotations() {
        document.clear()
        selectedAnnotationID = nil
        notifyChanged()
    }

    func deleteSelected() {
        guard let id = selectedAnnotationID else { return }
        document.remove(id: id)
        selectedAnnotationID = nil
        notifyChanged()
    }

    /// Commits any in-progress inline text edit programmatically (e.g. when
    /// the host wants to finalize the capture while a text field is still
    /// focused).
    func endTextEditing() {
        textEditingEndHandler?()
    }

    func render(over image: NSImage, canvasSize: CGSize) -> NSImage {
        AnnotationRenderer.render(document.annotations, over: image, canvasSize: canvasSize)
    }

    // MARK: - Editor-window extensions

    var canUndo: Bool { document.canUndo }
    var canRedo: Bool { document.canRedo }

    func setSource(_ image: NSImage, frame: CGRect) {
        sourceImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        sourceFrame = frame
        PixelCache.shared.removeAll()
        notifyChanged()
    }

    func renderContext(canvasBounds: CGRect) -> AnnotationRenderContext {
        AnnotationRenderContext(source: sourceImage, sourceFrame: sourceFrame, canvasBounds: canvasBounds, usesCache: true)
    }

    /// The current non-destructive crop, in canvas coordinates.
    var cropRect: CGRect? { AnnotationGeometry.crop(in: document.annotations)?.rect }

    /// Sets (one undo step) or clears the crop. Crops smaller than 4pt are ignored.
    func setCrop(_ rect: CGRect?) {
        let existing = AnnotationGeometry.crop(in: document.annotations)
        guard let rect = rect?.standardized, rect.width >= 4, rect.height >= 4 else {
            if let existing { removeAnnotation(id: existing.id) }
            return
        }
        if let existing {
            updateAnnotation(existing.with(rect: rect))
        } else {
            addAnnotation(Annotation(tool: .crop, rect: rect))
        }
    }

    /// The marks a user can see and select (everything but the crop entry).
    var visibleAnnotations: [Annotation] { document.annotations.filter { $0.tool != .crop } }

    // MARK: - Internal wiring used by AnnotationCanvasView / EditToolbarView

    /// Registers a closure invoked whenever document/tool/style state
    /// changes, in addition to `onChanged`. Lets the canvas view and the
    /// toolbar both react without needing to share the single public
    /// closure slot.
    func addObserver(_ observer: @escaping () -> Void) {
        observers.append(observer)
    }

    /// Lets `AnnotationCanvasView` supply the closure that actually commits
    /// its inline `NSTextField` overlay, so the public `endTextEditing()`
    /// has something to call.
    func setTextEditingEndHandler(_ handler: (() -> Void)?) {
        textEditingEndHandler = handler
    }

    func setIsEditingText(_ value: Bool) {
        guard isEditingText != value else { return }
        isEditingText = value
        notifyChanged()
    }

    func selectAnnotation(id: UUID?) {
        guard selectedAnnotationID != id else { return }
        selectedAnnotationID = id
        notifyChanged()
    }

    func addAnnotation(_ annotation: Annotation) {
        document.add(annotation)
        notifyChanged()
    }

    func updateAnnotation(_ annotation: Annotation) {
        document.update(annotation)
        notifyChanged()
    }

    func removeAnnotation(id: UUID) {
        document.remove(id: id)
        notifyChanged()
    }

    // MARK: - Private

    /// Toolbar style changes also restyle the currently selected annotation
    /// (e.g. select an arrow, pick a bigger line width -> the arrow grows).
    /// The annotation's own `fontSize` is preserved so recoloring selected
    /// text doesn't undo a manual scale-handle resize.
    private func applyStyleToSelection() {
        guard let id = selectedAnnotationID,
              var annotation = document.annotations.first(where: { $0.id == id }) else {
            return
        }
        var style = annotation.style
        style.color = currentStyle.color
        style.lineWidth = currentStyle.lineWidth
        style.isFilled = currentStyle.isFilled
        guard style.color != annotation.style.color
            || style.lineWidth != annotation.style.lineWidth
            || style.isFilled != annotation.style.isFilled else { return }
        annotation.style = style
        document.update(annotation)
    }

    private func notifyChanged() {
        onChanged?()
        for observer in observers {
            observer()
        }
    }
}
