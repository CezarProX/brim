// ScreenshotEditorModel.swift
// Brim
//
// State behind the "Edit screenshot" window: the annotation session, the
// canvas style, sidebar visibility and zoom. SwiftUI chrome (sidebar, tool
// strip) observes this object; the AppKit canvas host is driven by it.
// Annotation coordinates are the screenshot's own points, independent of
// zoom and crop, so the export is a pure function of (image, document, style).

import AppKit
import Combine

@MainActor
final class ScreenshotEditorModel: ObservableObject {
    let image: NSImage
    let session = EditorSession()
    let presets: StylePresetStore
    private(set) lazy var canvasHost = EditorCanvasHostView(model: self)

    @Published var style: CanvasStyle { didSet { styleDidChange(from: oldValue) } }
    @Published var isSidebarVisible = true
    /// Mirrors session state that SwiftUI renders (tool, colour, undo...).
    @Published private(set) var revision = 0
    @Published private(set) var zoom: CGFloat = 1
    @Published private(set) var isZoomToFit = true

    /// The document and look as last saved (initially: as opened).
    private var savedSignature = ""
    private var savedStyle: CanvasStyle

    init(image: NSImage, presets: StylePresetStore? = nil, style: CanvasStyle? = nil) {
        self.image = image
        let presets = presets ?? .shared
        self.presets = presets
        let start = style ?? presets.styleForNewCapture ?? .plain
        self.style = start
        self.savedStyle = start
        session.setSource(image, frame: CGRect(origin: .zero, size: image.size))
        session.currentStyle = AnnotationStyle(color: .systemRed, lineWidth: 4, fontSize: 22)
        session.addObserver { [weak self] in
            guard let self else { return }
            self.revision &+= 1
            self.canvasHost.sessionDidChange()
        }
    }

    // MARK: - Tools

    var currentTool: AnnotationTool? { session.currentTool }

    /// Picks `tool`; picking the active tool again returns to selection.
    func select(tool: AnnotationTool?) {
        session.endTextEditing()
        if tool == .crop { session.selectAnnotation(id: nil) }
        session.currentTool = session.currentTool == tool ? nil : tool
    }

    var annotationStyle: AnnotationStyle {
        get { session.currentStyle }
        set { session.currentStyle = newValue }
    }

    func undo() { session.endTextEditing(); session.undo() }
    func redo() { session.endTextEditing(); session.redo() }
    func deleteSelection() { session.deleteSelected() }
    func resetCrop() { session.setCrop(nil) }

    // MARK: - Style

    func toggleStyledBackground(_ isOn: Bool) {
        var next = isOn && style == .plain ? CanvasStyle.styledDefault : style
        next.isEnabled = isOn
        style = next
    }

    func apply(_ preset: StylePreset) { style = preset.style }

    func resetStyle() { style = .plain }

    @discardableResult
    func saveCurrentStyle(named name: String) -> StylePreset {
        presets.save(name: name, style: style)
    }

    private func styleDidChange(from old: CanvasStyle) {
        guard old != style else { return }
        canvasHost.styleDidChange()
    }

    // MARK: - Zoom

    func zoomIn() { canvasHost.setZoom(zoom * 1.25) }
    func zoomOut() { canvasHost.setZoom(zoom / 1.25) }
    func zoomToActualSize() { canvasHost.setZoom(1) }
    func zoomToFit() { canvasHost.zoomToFit() }

    func zoomDidChange(to value: CGFloat, fit: Bool) {
        if zoom != value { zoom = value }
        if isZoomToFit != fit { isZoomToFit = fit }
    }

    // MARK: - Export & dirty state

    func renderedImage() -> NSImage {
        session.endTextEditing()
        return StyledScreenshotExporter.render(image: image, annotations: session.document.annotations, style: style)
    }

    /// True once the user changed annotations, the crop or the look since
    /// opening (or since the last Done/save).
    var isEdited: Bool {
        Self.signature(of: session.document.annotations) != savedSignature || style != savedStyle
    }

    func markSaved() {
        savedSignature = Self.signature(of: session.document.annotations)
        savedStyle = style
    }

    /// A value-level fingerprint of the document (Annotation is not Equatable
    /// because of NSColor), so undoing back to the saved state reads as clean.
    static func signature(of annotations: [Annotation]) -> String {
        annotations.map { a in
            let points = a.points.map { "\($0.x),\($0.y)" }.joined(separator: ";")
            return "\(a.id)|\(a.tool.rawValue)|\(a.rect)|\(points)|\(a.text)|\(a.style.color)|\(a.style.lineWidth)|\(a.style.fontSize)|\(a.style.isFilled)"
        }.joined(separator: "\n")
    }
}
