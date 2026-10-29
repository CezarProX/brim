import AppKit
import Testing

@testable import Brim

/// Model behaviour of the editor's tools: shape creation, numbering, crop,
/// undo/redo, pixel tools, export and keyboard routing.
@MainActor
@Suite("Editor tools")
struct EditorToolsTests {
    private let style = AnnotationStyle(color: .systemRed, lineWidth: 4)

    // MARK: - Shapes

    @Test func dragsProduceTheRightGeometryPerTool() throws {
        let start = CGPoint(x: 10, y: 10), end = CGPoint(x: 70, y: 40)
        let rectTools: [AnnotationTool] = [.rectangle, .ellipse, .blur, .pixelate, .spotlight]
        for tool in rectTools {
            let shape = try #require(AnnotationCanvasView.shape(tool: tool, from: start, to: end, style: style))
            #expect(shape.rect == CGRect(x: 10, y: 10, width: 60, height: 30), "\(tool)")
        }
        let lens = try #require(AnnotationCanvasView.shape(tool: .magnifier, from: start, to: end, style: style))
        #expect(lens.rect == CGRect(x: 10, y: 10, width: 60, height: 60))
        let curve = try #require(AnnotationCanvasView.shape(tool: .curvedArrow, from: start, to: end, style: style))
        #expect(curve.points.count == 3 && curve.points.first == start && curve.points.last == end)
        #expect(AnnotationCanvasView.shape(tool: .counter, from: start, to: end, style: style) == nil)
    }

    @Test func curvedArrowBendsToTheLeftOfTheDrag() {
        let control = AnnotationGeometry.defaultControlPoint(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 0))
        #expect(control == CGPoint(x: 50, y: 25))
        let samples = AnnotationGeometry.curveSamples([CGPoint(x: 0, y: 0), control, CGPoint(x: 100, y: 0)])
        #expect(samples.first == CGPoint(x: 0, y: 0) && samples.last == CGPoint(x: 100, y: 0))
        #expect(abs(AnnotationGeometry.quadPoint([.zero, control, CGPoint(x: 100, y: 0)], t: 0.5).y - 12.5) < 0.001)
    }

    @Test func translatingMovesRectAndPointToolsAlike() {
        let rect = Annotation(tool: .ellipse, rect: CGRect(x: 0, y: 0, width: 10, height: 10))
        let curve = Annotation(tool: .curvedArrow, points: [.zero, CGPoint(x: 5, y: 5), CGPoint(x: 10, y: 0)])
        #expect(AnnotationGeometry.translated(rect, by: CGSize(width: 3, height: 4)).rect.origin == CGPoint(x: 3, y: 4))
        #expect(AnnotationGeometry.translated(curve, by: CGSize(width: 1, height: 1)).points[1] == CGPoint(x: 6, y: 6))
    }

    // MARK: - Step counter

    @Test func stepCountersNumberOnePastTheHighest() {
        let session = EditorSession()
        session.currentTool = .counter
        let canvas = AnnotationCanvasView(session: session)
        canvas.placeCounter(at: CGPoint(x: 20, y: 20))
        canvas.placeCounter(at: CGPoint(x: 60, y: 20))
        canvas.placeCounter(at: CGPoint(x: 100, y: 20))
        #expect(session.document.annotations.map(\.text) == ["1", "2", "3"])
        session.removeAnnotation(id: session.document.annotations[1].id)
        canvas.placeCounter(at: CGPoint(x: 140, y: 20))
        #expect(session.document.annotations.map(\.text) == ["1", "3", "4"])
        let badge = session.document.annotations[0].rect
        #expect(badge.midX == 20 && badge.midY == 20 && badge.width == AnnotationGeometry.counterDiameter(lineWidth: 3))
    }

    // MARK: - Crop and undo/redo

    @Test func cropIsOneUndoableEntryThatUpdatesInPlace() {
        let session = EditorSession()
        session.setCrop(CGRect(x: 10, y: 10, width: 100, height: 50))
        session.setCrop(CGRect(x: 20, y: 20, width: 80, height: 40))
        #expect(session.document.annotations.filter { $0.tool == .crop }.count == 1)
        #expect(session.cropRect == CGRect(x: 20, y: 20, width: 80, height: 40))
        #expect(session.visibleAnnotations.isEmpty)
        session.undo()
        #expect(session.cropRect == CGRect(x: 10, y: 10, width: 100, height: 50))
        session.undo()
        #expect(session.cropRect == nil)
        session.redo()
        #expect(session.cropRect == CGRect(x: 10, y: 10, width: 100, height: 50))
        session.setCrop(nil)
        #expect(session.cropRect == nil)
        session.setCrop(CGRect(x: 0, y: 0, width: 2, height: 2))
        #expect(session.cropRect == nil, "slivers are ignored")
    }

    @Test func undoRedoRestoresNewToolsAndFillStyle() {
        let session = EditorSession()
        session.addAnnotation(Annotation(tool: .ellipse, rect: CGRect(x: 0, y: 0, width: 20, height: 20), style: style))
        session.selectAnnotation(id: session.document.annotations[0].id)
        var filled = session.currentStyle
        filled.isFilled = true
        session.currentStyle = filled
        #expect(session.document.annotations[0].style.isFilled)
        session.undo()
        #expect(!session.document.annotations[0].style.isFilled)
        session.redo()
        #expect(session.document.annotations[0].style.isFilled)
        session.undo(); session.undo()
        #expect(session.document.annotations.isEmpty && !session.canUndo && session.canRedo)
    }

    // MARK: - Pixel tools

    private func stripes(width: Int = 200, height: Int = 100) throws -> NSImage {
        let ctx = try #require(StyledCanvasRenderer.makeContext(size: CGSize(width: width, height: height)))
        for x in stride(from: 0, to: width, by: 4) {
            ctx.setFillColor(x % 8 == 0 ? CGColor(gray: 0, alpha: 1) : CGColor(gray: 1, alpha: 1))
            ctx.fill(CGRect(x: x, y: 0, width: 4, height: height))
        }
        return NSImage(cgImage: try #require(ctx.makeImage()), size: CGSize(width: width / 2, height: height / 2))
    }

    private func luminance(_ image: NSImage, x: Int, yFromBottom: Int) throws -> CGFloat {
        let rep = NSBitmapImageRep(cgImage: try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil)))
        let color = try #require(rep.colorAt(x: x, y: rep.pixelsHigh - 1 - yFromBottom)?.usingColorSpace(.deviceRGB))
        return color.redComponent
    }

    @Test(arguments: [AnnotationTool.blur, .pixelate])
    func obscuringToolsChangeOnlyTheirRegion(tool: AnnotationTool) throws {
        let source = try stripes()
        let region = Annotation(tool: tool, rect: CGRect(x: 0, y: 0, width: 50, height: 50))
        let output = AnnotationRenderer.render([region], over: source, canvasSize: source.size)
        #expect(ImageEncoder.pixelSize(of: output) == CGSize(width: 200, height: 100))
        // Inside: stripes 4px wide get averaged towards grey (blur) or blocks (pixelate).
        let insideValues = try (0..<8).map { try luminance(output, x: 40 + $0, yFromBottom: 50) }
        let outsideValues = try (0..<8).map { try luminance(output, x: 140 + $0, yFromBottom: 50) }
        let spread: ([CGFloat]) -> CGFloat = { ($0.max() ?? 0) - ($0.min() ?? 0) }
        #expect(spread(outsideValues) > 0.9, "outside stays crisp")
        if tool == .blur { #expect(spread(insideValues) < 0.5, "blur softens stripes") }
        else { #expect(Set(insideValues.map { ($0 * 100).rounded() }).count <= 3, "pixelate makes blocks") }
    }

    @Test func spotlightDimsOutsideItsRect() throws {
        let ctx = try #require(StyledCanvasRenderer.makeContext(size: CGSize(width: 100, height: 100)))
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        let white = NSImage(cgImage: try #require(ctx.makeImage()), size: CGSize(width: 100, height: 100))
        let spot = Annotation(tool: .spotlight, rect: CGRect(x: 30, y: 30, width: 40, height: 40))
        let output = AnnotationRenderer.render([spot], over: white, canvasSize: white.size)
        let width = Int(ImageEncoder.pixelSize(of: output).width)
        let centre = try luminance(output, x: width / 2, yFromBottom: width / 2)
        let corner = try luminance(output, x: width / 20, yFromBottom: width / 20)
        #expect(centre > 0.98, "inside the spotlight stays untouched (\(centre))")
        #expect(corner < 0.6, "outside is dimmed (\(corner))")
    }

    @Test func magnifierShowsTheSourceEnlarged() throws {
        let source = try stripes()
        let lens = Annotation(tool: .magnifier, rect: CGRect(x: 20, y: 10, width: 30, height: 30), style: style)
        let output = AnnotationRenderer.render([lens], over: source, canvasSize: source.size)
        // At 2x, the 4px stripes become 8px: two adjacent pixels at the lens centre match.
        let a = try luminance(output, x: 70, yFromBottom: 50), b = try luminance(output, x: 71, yFromBottom: 50)
        #expect(abs(a - b) < 0.2)
    }

    // MARK: - Export

    @Test func exportAppliesCropAndStyleAtSourceResolution() throws {
        let source = try stripes(width: 400, height: 200)   // 200x100 pt @2x
        let annotations = [Annotation(tool: .crop, rect: CGRect(x: 50, y: 25, width: 100, height: 50))]
        let plain = StyledScreenshotExporter.render(image: source, annotations: annotations, style: .plain)
        #expect(plain.size == CGSize(width: 100, height: 50))
        #expect(ImageEncoder.pixelSize(of: plain) == CGSize(width: 200, height: 100))

        let styled = CanvasStyle(isEnabled: true, background: .solid(RGBAColor(hex: 0x336699)), padding: 0.1, aspect: .square)
        let output = StyledScreenshotExporter.render(image: source, annotations: annotations, style: styled)
        let layout = StyledCanvasLayout.make(contentSize: CGSize(width: 100, height: 50), style: styled)
        #expect(output.size == layout.canvasSize)
        #expect(ImageEncoder.pixelSize(of: output).width == (layout.canvasSize.width * 2).rounded())
    }

    @Test func editorModelTracksEditsAndSaves() throws {
        let store = StylePresetStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("qs-model-\(UUID().uuidString).json"))
        let model = ScreenshotEditorModel(image: try stripes(), presets: store)
        #expect(!model.isEdited)
        model.session.addAnnotation(Annotation(tool: .arrow, points: [.zero, CGPoint(x: 9, y: 9)]))
        #expect(model.isEdited)
        model.undo()
        #expect(!model.isEdited, "undoing back to the opened state is clean")
        model.toggleStyledBackground(true)
        #expect(model.style.isEnabled && model.isEdited)
        model.markSaved()
        #expect(!model.isEdited)
    }

    // MARK: - Keyboard

    @Test func keyboardShortcutsMapToCommands() {
        func map(_ chars: String, _ code: UInt16 = 0, _ mods: NSEvent.ModifierFlags = [], editing: Bool = false) -> EditorKeyCommand? {
            EditorKeyCommand.command(keyCode: code, characters: chars, modifiers: mods, isEditingText: editing)
        }
        #expect(map("\u{1b}", 53) == .escape)
        #expect(map("w", 13, .command) == .close)
        #expect(map("c", 8, .command) == .copy)
        #expect(map("c", 8, .command, editing: true) == nil)
        #expect(map("s", 1, .command) == .save)
        #expect(map("z", 6, .command) == .undo)
        #expect(map("z", 6, [.command, .shift]) == .redo)
        #expect(map("\r", 36, .command) == .done)
        #expect(map("a") == .tool(.arrow))
        #expect(map("v") == .tool(nil))
        #expect(map("n") == .tool(.counter))
        #expect(map("a", editing: true) == nil)
        #expect(map("", 51) == .delete)
        #expect(map("=", 24, .command) == .zoomIn)
        #expect(map("0", 29, .command) == .actualSize)
    }

    @Test func everyReferenceToolIsInTheToolStripWithAUniqueShortcut() {
        let tools = Set(EditorToolItem.all.compactMap(\.tool))
        let expected: Set<AnnotationTool> = [.text, .crop, .arrow, .curvedArrow, .line, .rectangle, .ellipse, .pen,
                                             .highlighter, .blur, .pixelate, .spotlight, .magnifier, .counter]
        #expect(tools == expected)
        #expect(EditorToolItem.all.contains { $0.tool == nil }, "select tool")
        #expect(Set(EditorToolItem.all.map(\.shortcut)).count == EditorToolItem.all.count)
    }
}
