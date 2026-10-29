// EditorCanvasHostView.swift
// Brim
//
// The editor window's canvas: an NSScrollView (pinch / ⌘+ / ⌘− zoom, fit)
// whose document is the styled canvas. View tree:
//
//   NSScrollView (magnification = zoom)
//   └─ EditorCanvasDocumentView      backdrop: background + shadow (pre-rendered)
//      └─ EditorScreenshotView       rounded, clipped; bounds = visible image rect
//         └─ AnnotationCanvasView    bounds = visible image rect (image points)
//
// The visible image rect is the crop, or the whole image while the crop
// tool is active, so annotation coordinates never depend on zoom or crop.

import AppKit

@MainActor
final class EditorCanvasHostView: NSView {
    private unowned let model: ScreenshotEditorModel
    private let scrollView = NSScrollView()
    private let documentView = EditorCanvasDocumentView()
    private let screenshotView: EditorScreenshotView
    let canvas: AnnotationCanvasView
    private var canvasLayout = StyledCanvasLayout.make(contentSize: CGSize(width: 1, height: 1), style: .plain)
    private var visibleImageRect = CGRect.zero
    private var fitsOnResize = true
    private var lastFittedSize = CGSize.zero

    static let canvasBackground = NSColor(srgbRed: 0.075, green: 0.075, blue: 0.085, alpha: 1)
    static let fitMargin: CGFloat = 28

    init(model: ScreenshotEditorModel) {
        self.model = model
        self.screenshotView = EditorScreenshotView(image: model.image, session: model.session)
        self.canvas = AnnotationCanvasView(session: model.session)
        super.init(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        configureScrollView()
        documentView.addSubview(screenshotView)
        screenshotView.addSubview(canvas)
        documentView.onBackgroundClick = { [weak self] in self?.deselect() }
        screenshotView.onBackgroundClick = { [weak self] in self?.deselect() }
        relayout()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func configureScrollView() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.contentView = EditorCenteringClipView()
        scrollView.documentView = documentView
        scrollView.drawsBackground = true
        scrollView.backgroundColor = Self.canvasBackground
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.allowsMagnification = true
        scrollView.minMagnification = 0.05
        scrollView.maxMagnification = 8
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        NotificationCenter.default.addObserver(
            self, selector: #selector(liveMagnifyEnded), name: NSScrollView.didEndLiveMagnifyNotification, object: scrollView
        )
    }

    // MARK: - Model hooks

    func sessionDidChange() {
        let target = targetVisibleRect()
        if target != visibleImageRect { relayout() } else { canvas.needsDisplay = true }
    }

    func styleDidChange() { relayout() }

    private func targetVisibleRect() -> CGRect {
        let full = CGRect(origin: .zero, size: model.image.size)
        if model.session.currentTool == .crop { return full }
        return model.session.cropRect?.intersection(full) ?? full
    }

    /// Recomputes the layout for the current crop + style and re-renders the backdrop.
    func relayout() {
        visibleImageRect = targetVisibleRect()
        canvasLayout = StyledCanvasLayout.make(contentSize: visibleImageRect.size, style: model.style)
        documentView.setFrameSize(canvasLayout.canvasSize)
        documentView.backdrop = model.style.isEnabled
            ? StyledCanvasRenderer.renderBackdrop(layout: canvasLayout.scaled(by: backdropScale),
                                                 background: BackgroundResolver.resolve(model.style.background))
            : nil
        documentView.needsDisplay = true

        screenshotView.frame = canvasLayout.contentRect
        screenshotView.bounds = visibleImageRect
        screenshotView.cornerRadius = canvasLayout.cornerRadius
        canvas.frame = visibleImageRect
        canvas.bounds = visibleImageRect
        canvas.needsDisplay = true
        screenshotView.needsDisplay = true
        if fitsOnResize { zoomToFit() }
    }

    /// The backdrop is a preview; cap it so huge canvases stay cheap.
    private var backdropScale: CGFloat {
        let longSide = max(canvasLayout.canvasSize.width, canvasLayout.canvasSize.height)
        return min(1, 2400 / max(1, longSide))
    }

    private func deselect() {
        model.session.endTextEditing()
        model.session.selectAnnotation(id: nil)
        window?.makeFirstResponder(canvas)
    }

    // MARK: - Zoom

    func zoomToFit() {
        fitsOnResize = true
        // The scroll view is pinned to our bounds; use them so a fit during
        // our own resize does not read the scroll view's stale frame.
        let viewport = CGSize(width: bounds.width - 2 * Self.fitMargin, height: bounds.height - 2 * Self.fitMargin)
        guard viewport.width > 0, viewport.height > 0, canvasLayout.canvasSize.width > 0 else { return }
        lastFittedSize = bounds.size
        // Fit never upscales: a small crop shown at 400% would only look soft.
        let scale = min(viewport.width / canvasLayout.canvasSize.width, viewport.height / canvasLayout.canvasSize.height, 1)
        applyMagnification(max(scrollView.minMagnification, scale))
    }

    func setZoom(_ value: CGFloat) {
        fitsOnResize = false
        applyMagnification(min(scrollView.maxMagnification, max(scrollView.minMagnification, value)))
    }

    private func applyMagnification(_ value: CGFloat) {
        let center = CGPoint(x: documentView.bounds.midX, y: documentView.bounds.midY)
        scrollView.setMagnification(value, centeredAt: center)
        model.zoomDidChange(to: value, fit: fitsOnResize)
    }

    @objc private func liveMagnifyEnded() {
        fitsOnResize = false
        model.zoomDidChange(to: scrollView.magnification, fit: false)
    }

    /// Refits after a resize. Only magnification changes here (clip-view
    /// bounds), never a frame: touching constraint-driven frames inside a
    /// layout pass makes AppKit throw from SwiftUI's hosting layout.
    override func layout() {
        super.layout()
        guard fitsOnResize, bounds.size != lastFittedSize else { return }
        zoomToFit()
    }
}

/// Keeps a document smaller than the viewport centred instead of pinned bottom-left.
private final class EditorCenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let document = documentView else { return rect }
        if rect.width > document.frame.width { rect.origin.x = (document.frame.width - rect.width) / 2 }
        if rect.height > document.frame.height { rect.origin.y = (document.frame.height - rect.height) / 2 }
        return rect
    }
}

/// Draws the pre-rendered backdrop (background + shadow) behind the screenshot.
@MainActor
final class EditorCanvasDocumentView: NSView {
    var backdrop: CGImage?
    var onBackgroundClick: (() -> Void)?

    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard let backdrop, let cg = NSGraphicsContext.current?.cgContext else { return }
        cg.interpolationQuality = .high
        cg.draw(backdrop, in: bounds)
    }

    override func mouseDown(with event: NSEvent) { onBackgroundClick?() }
}

/// The screenshot itself, clipped to the style's rounded corners. Its
/// bounds are the visible image rect, so it draws the whole image at the
/// origin and the crop falls out of the bounds.
@MainActor
final class EditorScreenshotView: NSView {
    private let image: NSImage
    private let session: EditorSession
    var onBackgroundClick: (() -> Void)?
    var cornerRadius: CGFloat = 0 {
        didSet { layer?.cornerRadius = cornerRadius }
    }

    init(image: NSImage, session: EditorSession) {
        self.image = image
        self.session = session
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        image.draw(in: CGRect(origin: .zero, size: image.size), from: .zero, operation: .sourceOver, fraction: 1)
    }

    override func mouseDown(with event: NSEvent) { onBackgroundClick?() }
}
