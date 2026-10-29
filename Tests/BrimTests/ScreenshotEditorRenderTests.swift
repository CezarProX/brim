import AppKit
import Testing

@testable import Brim

/// Renders the "Edit screenshot" window (sidebar open, styled background on,
/// several annotations) and the styled export to .renders/ for visual review.
/// Synthetic artwork only: no screen capture, clipboard or user files.
@MainActor
@Suite(.serialized)
struct ScreenshotEditorRenderTests {
    private static let rendersDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent(".renders")

    @Test func rendersTheEditorWindowAndStyledExport() async throws {
        let store = StylePresetStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("qs-render-\(UUID().uuidString).json"))
        store.save(name: "Aurora", style: CanvasStyle(isEnabled: true, background: .gradient(id: "aurora")))
        store.save(name: "Sunset", style: CanvasStyle(isEnabled: true, background: .gradient(id: "sunset"), corners: .large))
        store.save(name: "Slate", style: CanvasStyle(isEnabled: true, background: .gradient(id: "slate"), padding: 0.05))
        let image = try Self.syntheticScreenshot()
        let controller = ShelfEditorWindowController(image: image, onSaveToShelf: { _ in }, presets: store)
        let window = try #require(controller.window)
        window.setContentSize(CGSize(width: 1280, height: 800))
        controller.model.style = CanvasStyle(isEnabled: true, background: .gradient(id: "aurora"), padding: 0.08,
                                            shadow: 0.6, corners: .medium)
        Self.annotate(controller.model.session)
        controller.model.session.currentTool = .arrow
        window.orderFrontRegardless()
        defer { window.orderOut(nil); window.close() }
        try await Task.sleep(for: .milliseconds(900))

        let frameView = try #require(window.contentView?.superview)
        frameView.layoutSubtreeIfNeeded()
        let bitmap = try #require(frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds))
        frameView.cacheDisplay(in: frameView.bounds, to: bitmap)
        try write(bitmap, name: "editor-window.png")
        #expect(bitmap.pixelsWide >= 1280)

        let export = controller.model.renderedImage()
        let layout = StyledCanvasLayout.make(contentSize: image.size, style: controller.model.style)
        #expect(export.size == layout.canvasSize)
        #expect(ImageEncoder.pixelSize(of: export).width == (layout.canvasSize.width * 2).rounded())
        let exportRep = NSBitmapImageRep(cgImage: try #require(export.cgImage(forProposedRect: nil, context: nil, hints: nil)))
        try write(exportRep, name: "editor-styled-export.png")

        // Crop mode with the sidebar collapsed: whole image, crop frame, dimmed outside.
        controller.model.session.setCrop(CGRect(x: 160, y: 40, width: 540, height: 300))
        controller.model.isSidebarVisible = false
        controller.model.select(tool: .crop)
        try await Task.sleep(for: .milliseconds(700))
        frameView.layoutSubtreeIfNeeded()
        let cropBitmap = try #require(frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds))
        frameView.cacheDisplay(in: frameView.bounds, to: cropBitmap)
        try write(cropBitmap, name: "editor-window-crop.png")
        controller.model.select(tool: nil)
        controller.model.session.setCrop(nil)

        controller.model.style = CanvasStyle(isEnabled: true, background: .gradient(id: "sunset"), padding: 0.12,
                                            shadow: 0.8, corners: .large, aspect: .wide)
        let wide = controller.model.renderedImage()
        try write(NSBitmapImageRep(cgImage: try #require(wide.cgImage(forProposedRect: nil, context: nil, hints: nil))),
                  name: "editor-styled-export-16x9.png")
        #expect(abs(wide.size.width / wide.size.height - 16.0 / 9.0) < 0.01)
    }

    @Test func rendersTheGradientLibrary() throws {
        let columns = 5, tile = 160, gap = 12
        let rows = (GradientLibrary.presets.count + columns - 1) / columns
        let size = CGSize(width: columns * (tile + gap) + gap, height: rows * (tile + gap) + gap)
        let ctx = try #require(StyledCanvasRenderer.makeContext(size: size))
        ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: size))
        for (index, preset) in GradientLibrary.presets.enumerated() {
            let x = gap + (index % columns) * (tile + gap)
            let y = Int(size.height) - (index / columns + 1) * (tile + gap)
            ctx.saveGState()
            ctx.addPath(StyledCanvasRenderer.roundedPath(CGRect(x: x, y: y, width: tile, height: tile), radius: 14))
            ctx.clip()
            StyledCanvasRenderer.drawGradient(preset, in: ctx, rect: CGRect(x: x, y: y, width: tile, height: tile))
            ctx.restoreGState()
        }
        try write(NSBitmapImageRep(cgImage: try #require(ctx.makeImage())), name: "editor-gradients.png")
    }

    private func write(_ bitmap: NSBitmapImageRep, name: String) throws {
        try FileManager.default.createDirectory(at: Self.rendersDir, withIntermediateDirectories: true)
        try #require(bitmap.representation(using: .png, properties: [:])).write(to: Self.rendersDir.appendingPathComponent(name))
    }

    /// One of each kind of mark, in screenshot points (720 x 450).
    static func annotate(_ session: EditorSession) {
        let red = AnnotationStyle(color: .systemRed, lineWidth: 4, fontSize: 22)
        let marks: [Annotation] = [
            Annotation(tool: .blur, rect: CGRect(x: 176, y: 22, width: 250, height: 52)),
            Annotation(tool: .rectangle, rect: CGRect(x: 190, y: 190, width: 250, height: 110), style: red),
            Annotation(tool: .arrow, points: [CGPoint(x: 560, y: 120), CGPoint(x: 450, y: 210)], style: red),
            Annotation(tool: .curvedArrow, points: [CGPoint(x: 120, y: 90), CGPoint(x: 150, y: 170), CGPoint(x: 200, y: 200)],
                       style: AnnotationStyle(color: .systemYellow, lineWidth: 4)),
            Annotation(tool: .highlighter, points: [CGPoint(x: 210, y: 150), CGPoint(x: 330, y: 150)],
                       style: AnnotationStyle(color: .systemYellow, lineWidth: 5)),
            Annotation(tool: .counter, rect: AnnotationGeometry.counterRect(centeredAt: CGPoint(x: 190, y: 300), lineWidth: 4),
                       text: "1", style: red),
            Annotation(tool: .counter, rect: AnnotationGeometry.counterRect(centeredAt: CGPoint(x: 560, y: 120), lineWidth: 4),
                       text: "2", style: AnnotationStyle(color: .systemBlue, lineWidth: 4)),
            Annotation(tool: .text, rect: CGRect(x: 455, y: 84, width: 0, height: 0), text: "Ship it!", style: red),
            Annotation(tool: .magnifier, rect: CGRect(x: 600, y: 16, width: 80, height: 80),
                       style: AnnotationStyle(color: .white, lineWidth: 3))
        ]
        for mark in marks { session.addAnnotation(mark) }
        session.selectAnnotation(id: marks[1].id)
    }

    /// A fake app window: title bar, sidebar, cards and text lines (720 x 450 pt at 2x).
    static func syntheticScreenshot() throws -> NSImage {
        let w = 1440, h = 900
        let ctx = try #require(StyledCanvasRenderer.makeContext(size: CGSize(width: w, height: h)))
        func fill(_ gray: CGFloat, _ rect: CGRect) { ctx.setFillColor(CGColor(gray: gray, alpha: 1)); ctx.fill(rect) }
        func fill(_ color: CGColor, _ rect: CGRect, radius: CGFloat = 0) {
            ctx.setFillColor(color)
            ctx.addPath(StyledCanvasRenderer.roundedPath(rect, radius: radius)); ctx.fillPath()
        }
        fill(0.98, CGRect(x: 0, y: 0, width: w, height: h))
        fill(0.93, CGRect(x: 0, y: h - 76, width: w, height: 76))
        for (i, hex) in [0xFF5F57, 0xFEBC2E, 0x28C840].enumerated() {
            fill(RGBAColor(hex: UInt32(hex)).cgColor, CGRect(x: 28 + i * 40, y: h - 52, width: 26, height: 26), radius: 13)
        }
        fill(0.95, CGRect(x: 0, y: 0, width: 300, height: h - 76))
        for row in 0..<9 {
            fill(row == 2 ? RGBAColor(hex: 0x0A84FF).cgColor : CGColor(gray: 0.82, alpha: 1),
                 CGRect(x: 30, y: h - 140 - row * 64, width: row == 2 ? 240 : 180, height: 30), radius: 8)
        }
        let cards: [(UInt32, CGRect)] = [
            (0xE8F0FF, CGRect(x: 360, y: 420, width: 540, height: 360)),
            (0xFFF1E0, CGRect(x: 940, y: 560, width: 440, height: 220)),
            (0xE6F8EC, CGRect(x: 940, y: 300, width: 440, height: 220))
        ]
        for (hex, rect) in cards { fill(RGBAColor(hex: hex).cgColor, rect, radius: 22) }
        for line in 0..<5 {
            fill(0.7, CGRect(x: 400, y: 700 - line * 52, width: [420, 360, 440, 300, 380][line], height: 18))
        }
        for line in 0..<4 { fill(0.78, CGRect(x: 360, y: 300 - line * 60, width: [520, 480, 540, 400][line], height: 22)) }
        fill(RGBAColor(hex: 0x0A84FF).cgColor, CGRect(x: 1180, y: 80, width: 200, height: 64), radius: 32)
        return NSImage(cgImage: try #require(ctx.makeImage()), size: CGSize(width: 720, height: 450))
    }
}
