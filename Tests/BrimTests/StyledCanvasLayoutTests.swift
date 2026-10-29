import AppKit
import Testing

@testable import Brim

@Suite("Styled canvas layout")
struct StyledCanvasLayoutTests {
    private let content = CGSize(width: 800, height: 600)

    @Test func disabledStyleIsThePlainContent() {
        let layout = StyledCanvasLayout.make(contentSize: content, style: .plain)
        #expect(layout.canvasSize == content)
        #expect(layout.contentRect == CGRect(origin: .zero, size: content))
        #expect(layout.cornerRadius == 0)
        #expect(layout.shadowOpacity == 0)
    }

    @Test func paddingIsAFractionOfTheMeanSide() {
        let style = CanvasStyle(isEnabled: true, padding: 0.1, shadow: 0, corners: .square)
        let layout = StyledCanvasLayout.make(contentSize: content, style: style)
        // mean side = 700 -> 70pt each side
        #expect(layout.canvasSize == CGSize(width: 940, height: 740))
        #expect(layout.contentRect == CGRect(x: 70, y: 70, width: 800, height: 600))
    }

    @Test func paddingIsClampedToTheMaximum() {
        let style = CanvasStyle(isEnabled: true, padding: 5)
        let layout = StyledCanvasLayout.make(contentSize: content, style: style)
        #expect(layout.contentRect.minX == 700 * CGFloat(CanvasStyle.maxPadding))
    }

    @Test(arguments: [(CornerPreset.square, 0.0), (.small, 0.009), (.medium, 0.017), (.large, 0.03)])
    func cornerRadiusScalesWithTheContent(preset: CornerPreset, factor: Double) {
        let style = CanvasStyle(isEnabled: true, corners: preset)
        let layout = StyledCanvasLayout.make(contentSize: content, style: style)
        let expected = CGFloat(factor) * (800 * 600 as CGFloat).squareRoot()
        #expect(abs(layout.cornerRadius - expected) < 0.001)
        #expect(StyledCanvasLayout.make(contentSize: CGSize(width: 1600, height: 1200), style: style).cornerRadius
                == layout.cornerRadius * 2)
    }

    @Test func cornerRadiusNeverExceedsHalfTheShortSide() {
        let style = CanvasStyle(isEnabled: true, corners: .large)
        let layout = StyledCanvasLayout.make(contentSize: CGSize(width: 4000, height: 10), style: style)
        #expect(layout.cornerRadius <= 5)
    }

    @Test(arguments: [AspectPreset.wide, .classic, .square, .portrait, .twitter])
    func aspectPresetsProduceTheirRatioAndContainTheContent(aspect: AspectPreset) throws {
        let style = CanvasStyle(isEnabled: true, padding: 0.05, aspect: aspect)
        let layout = StyledCanvasLayout.make(contentSize: content, style: style)
        let ratio = try #require(aspect.ratio)
        #expect(abs(layout.canvasSize.width / layout.canvasSize.height - ratio) < 0.0001)
        let canvas = CGRect(origin: .zero, size: layout.canvasSize)
        #expect(canvas.contains(layout.contentRect))
        // grows along one axis only: the other keeps exactly content + 2 * padding
        let padded = CGSize(width: 800 + 70, height: 600 + 70)
        #expect(layout.canvasSize.width == padded.width || layout.canvasSize.height == padded.height)
    }

    @Test func alignmentPlacesContentInTheSpareRoom() {
        var style = CanvasStyle(isEnabled: true, padding: 0, aspect: .wide, alignment: .leading)
        let leading = StyledCanvasLayout.make(contentSize: content, style: style)
        #expect(leading.contentRect.minX == 0)
        #expect(leading.contentRect.midY == leading.canvasSize.height / 2)
        style.alignment = .bottomTrailing
        let trailing = StyledCanvasLayout.make(contentSize: content, style: style)
        #expect(trailing.contentRect.maxX == trailing.canvasSize.width)
        #expect(trailing.contentRect.minY == 0)
        style.alignment = .center
        let centered = StyledCanvasLayout.make(contentSize: content, style: style)
        #expect(centered.contentRect.midX == centered.canvasSize.width / 2)
    }

    @Test func shadowStrengthDrivesBlurAndOpacity() {
        let none = StyledCanvasLayout.make(contentSize: content, style: CanvasStyle(isEnabled: true, shadow: 0))
        let full = StyledCanvasLayout.make(contentSize: content, style: CanvasStyle(isEnabled: true, shadow: 1))
        #expect(none.shadowOpacity == 0 && none.shadowBlur == 0)
        #expect(full.shadowBlur > 0 && full.shadowOpacity > 0.5)
        #expect(full.shadowOffset.height < 0)
    }

    @Test func scalingMultipliesEveryLength() {
        let layout = StyledCanvasLayout.make(contentSize: content, style: CanvasStyle(isEnabled: true, roundsOuterCorners: true))
        let doubled = layout.scaled(by: 2)
        #expect(doubled.canvasSize == CGSize(width: layout.canvasSize.width * 2, height: layout.canvasSize.height * 2))
        #expect(doubled.contentRect.origin.x == layout.contentRect.origin.x * 2)
        #expect(doubled.cornerRadius == layout.cornerRadius * 2)
        #expect(doubled.outerCornerRadius == layout.outerCornerRadius * 2 && layout.outerCornerRadius > 0)
    }

    @Test func styleDecodingToleratesMissingKeysAndClampsValues() throws {
        let json = #"{"isEnabled": true, "padding": 9, "shadow": -1}"#
        let style = try JSONDecoder().decode(CanvasStyle.self, from: Data(json.utf8))
        #expect(style.isEnabled)
        #expect(style.padding == CanvasStyle.maxPadding)
        #expect(style.shadow == 0)
        #expect(style.corners == .medium)
        #expect(style.background == .gradient(id: GradientLibrary.defaultID))
    }

    @Test func gradientLibraryHasTwentyUniqueReadablePresets() {
        #expect(GradientLibrary.presets.count == 20)
        #expect(Set(GradientLibrary.presets.map(\.id)).count == 20)
        #expect(GradientLibrary.presets.allSatisfy { $0.stops.count >= 2 })
        #expect(GradientLibrary.preset(id: GradientLibrary.defaultID) != nil)
    }
}

@MainActor
@Suite("Styled canvas renderer")
struct StyledCanvasRendererTests {
    private func solidContent(width: Int, height: Int) throws -> CGImage {
        let ctx = try #require(StyledCanvasRenderer.makeContext(size: CGSize(width: width, height: height)))
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try #require(ctx.makeImage())
    }

    @Test func renderOutputsCanvasSizeTimesScaleInPixels() throws {
        let style = CanvasStyle(isEnabled: true, background: .solid(RGBAColor(hex: 0x0000FF)), padding: 0.1, aspect: .square)
        let image = try #require(StyledCanvasRenderer.render(
            content: try solidContent(width: 400, height: 200), contentSize: CGSize(width: 200, height: 100),
            style: style, background: .solid(RGBAColor(hex: 0x0000FF).cgColor), scale: 2
        ))
        let layout = StyledCanvasLayout.make(contentSize: CGSize(width: 200, height: 100), style: style)
        #expect(image.width == Int((layout.canvasSize.width * 2).rounded()))
        #expect(image.height == image.width)
    }

    @Test func backgroundFillsTheCornersAndContentFillsTheMiddle() throws {
        let style = CanvasStyle(isEnabled: true, padding: 0.2, shadow: 0, corners: .square)
        let blue = RGBAColor(hex: 0x0000FF)
        let image = try #require(StyledCanvasRenderer.render(
            content: try solidContent(width: 100, height: 100), contentSize: CGSize(width: 100, height: 100),
            style: style, background: .solid(blue.cgColor), scale: 1
        ))
        let bitmap = NSBitmapImageRep(cgImage: image)
        let corner = try #require(bitmap.colorAt(x: 2, y: 2)?.usingColorSpace(.sRGB))
        let middle = try #require(bitmap.colorAt(x: image.width / 2, y: image.height / 2)?.usingColorSpace(.sRGB))
        #expect(corner.blueComponent > 0.9 && corner.redComponent < 0.1)
        #expect(middle.redComponent > 0.95 && middle.greenComponent > 0.95)
    }

    @Test func roundedOuterCornersLeaveTransparentPixels() throws {
        let style = CanvasStyle(isEnabled: true, padding: 0.2, roundsOuterCorners: true)
        let image = try #require(StyledCanvasRenderer.render(
            content: nil, contentSize: CGSize(width: 300, height: 200),
            style: style, background: .solid(RGBAColor(hex: 0xFF0000).cgColor), scale: 1
        ))
        let bitmap = NSBitmapImageRep(cgImage: image)
        #expect((bitmap.colorAt(x: 0, y: 0)?.alphaComponent ?? 1) < 0.05)
        #expect((bitmap.colorAt(x: image.width / 2, y: 2)?.alphaComponent ?? 0) > 0.95)
    }

    @Test func shadowDarkensBelowTheContentNotAbove() throws {
        let style = CanvasStyle(isEnabled: true, padding: 0.25, shadow: 1, corners: .square)
        let image = try #require(StyledCanvasRenderer.render(
            content: try solidContent(width: 200, height: 200), contentSize: CGSize(width: 200, height: 200),
            style: style, background: .solid(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)), scale: 1
        ))
        let layout = StyledCanvasLayout.make(contentSize: CGSize(width: 200, height: 200), style: style)
        let bitmap = NSBitmapImageRep(cgImage: image)
        // NSBitmapImageRep rows run top-down.
        let x = Int(layout.contentRect.midX)
        let belowRow = image.height - Int(layout.contentRect.minY) + 6
        let aboveRow = image.height - Int(layout.contentRect.maxY) - 6
        let below = try #require(bitmap.colorAt(x: x, y: belowRow)?.usingColorSpace(.sRGB)).redComponent
        let above = try #require(bitmap.colorAt(x: x, y: aboveRow)?.usingColorSpace(.sRGB)).redComponent
        #expect(below < above, "shadow should fall below the content (below \(below), above \(above))")
        #expect(below < 0.9)
    }

    @Test func everyGradientRendersOpaqueVariedPixels() throws {
        for preset in GradientLibrary.presets {
            let ctx = try #require(StyledCanvasRenderer.makeContext(size: CGSize(width: 64, height: 64)))
            StyledCanvasRenderer.drawGradient(preset, in: ctx, rect: CGRect(x: 0, y: 0, width: 64, height: 64))
            let bitmap = NSBitmapImageRep(cgImage: try #require(ctx.makeImage()))
            let a = try #require(bitmap.colorAt(x: 2, y: 2)), b = try #require(bitmap.colorAt(x: 61, y: 61))
            #expect(a.alphaComponent > 0.99, "\(preset.id) must be opaque")
            #expect(a != b, "\(preset.id) should not be flat")
        }
    }
}
