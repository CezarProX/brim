// AnnotationRenderer+Pixels.swift
// Brim
//
// Tools that read the screenshot's own pixels: blur, pixelate and the
// magnifier lens, plus the spotlight veil. Pixel work happens on the
// source CGImage at full resolution, so the export is as sharp as the
// capture; the live canvas reuses results through a small cache keyed by
// region, so dragging other annotations does not re-run the filters.

import AppKit
import CoreImage

extension AnnotationRenderer {

    // MARK: - Blur / pixelate

    static func drawObscured(_ annotation: Annotation, context: AnnotationRenderContext) {
        let rect = annotation.rect.standardized
        guard rect.width >= 1, rect.height >= 1 else { return }
        guard let pixelRect = context.sourcePixelRect(for: rect),
              let processed = obscuredImage(annotation.tool, pixelRect: pixelRect, context: context) else {
            drawObscuredPlaceholder(in: rect)
            return
        }
        guard let cg = NSGraphicsContext.current?.cgContext else { return }
        cg.saveGState()
        cg.clip(to: rect)
        cg.interpolationQuality = annotation.tool == .pixelate ? .none : .high
        cg.draw(processed, in: context.canvasRect(forPixelRect: pixelRect))
        cg.restoreGState()
    }

    /// Without source pixels (the in-place overlay) show a neutral frosted
    /// block so the region still reads as "hidden".
    private static func drawObscuredPlaceholder(in rect: CGRect) {
        NSColor(white: 0.55, alpha: 0.85).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3).fill()
    }

    private static func obscuredImage(_ tool: AnnotationTool, pixelRect: CGRect, context: AnnotationRenderContext) -> CGImage? {
        guard let source = context.source else { return nil }
        let key = PixelCache.key(tool: tool, rect: pixelRect, source: source)
        if context.usesCache, let cached = PixelCache.shared.image(for: key) { return cached }
        guard let region = source.cropping(to: pixelRect) else { return nil }
        let result = tool == .pixelate
            ? pixelated(region, blockSize: max(4, 10 * context.pixelScale))
            : blurred(region, sigma: max(4, 9 * context.pixelScale))
        if context.usesCache, let result { PixelCache.shared.store(result, for: key) }
        return result
    }

    static func blurred(_ image: CGImage, sigma: CGFloat) -> CGImage? {
        let input = CIImage(cgImage: image)
        let output = input.clampedToExtent().applyingGaussianBlur(sigma: Double(sigma)).cropped(to: input.extent)
        return PixelCache.ciContext.createCGImage(output, from: input.extent)
    }

    /// Mosaic by downsampling to one pixel per block; drawn back with
    /// nearest-neighbour interpolation that becomes crisp square blocks.
    static func pixelated(_ image: CGImage, blockSize: CGFloat) -> CGImage? {
        let width = max(1, Int((CGFloat(image.width) / blockSize).rounded(.up)))
        let height = max(1, Int((CGFloat(image.height) / blockSize).rounded(.up)))
        guard let small = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        small.interpolationQuality = .medium
        small.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return small.makeImage()
    }

    // MARK: - Magnifier

    static let magnification: CGFloat = 2

    static func drawMagnifier(_ annotation: Annotation, context: AnnotationRenderContext) {
        let lens = annotation.rect.standardized
        guard lens.width >= 4, lens.height >= 4 else { return }
        let circle = NSBezierPath(ovalIn: lens)

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.4)
        shadow.shadowBlurRadius = lens.width * 0.08
        shadow.shadowOffset = NSSize(width: 0, height: -lens.width * 0.03)
        shadow.set()
        NSColor.black.setFill()
        circle.fill()
        NSGraphicsContext.restoreGraphicsState()

        let sample = CGRect(
            x: lens.midX - lens.width / (2 * magnification),
            y: lens.midY - lens.height / (2 * magnification),
            width: lens.width / magnification,
            height: lens.height / magnification
        )
        if let cg = NSGraphicsContext.current?.cgContext,
           let pixelRect = context.sourcePixelRect(for: sample),
           let region = context.source?.cropping(to: pixelRect) {
            // Where the (possibly edge-clamped) sample lands inside the lens.
            let covered = context.canvasRect(forPixelRect: pixelRect)
            let target = CGRect(
                x: lens.midX + (covered.minX - sample.midX) * magnification,
                y: lens.midY + (covered.minY - sample.midY) * magnification,
                width: covered.width * magnification,
                height: covered.height * magnification
            )
            cg.saveGState()
            circle.addClip()
            cg.interpolationQuality = .high
            cg.draw(region, in: target)
            cg.restoreGState()
        }

        circle.lineWidth = max(2, annotation.style.lineWidth)
        annotation.style.color.setStroke()
        circle.stroke()
        let inner = NSBezierPath(ovalIn: lens.insetBy(dx: circle.lineWidth / 2 + 0.5, dy: circle.lineWidth / 2 + 0.5))
        inner.lineWidth = 1
        NSColor.white.withAlphaComponent(0.5).setStroke()
        inner.stroke()
    }

    // MARK: - Spotlight

    static let spotlightVeilAlpha: CGFloat = 0.55

    /// Dims `context.canvasBounds` except for every spotlight rect.
    static func drawSpotlightVeil(_ spotlights: [Annotation], context: AnnotationRenderContext) {
        let holes = spotlights.map { $0.rect.standardized }.filter { $0.width > 0 && $0.height > 0 }
        guard !holes.isEmpty else { return }
        let bounds = context.canvasBounds.isEmpty
            ? holes.reduce(holes[0]) { $0.union($1) }.insetBy(dx: -4000, dy: -4000)
            : context.canvasBounds
        guard let cg = NSGraphicsContext.current?.cgContext else { return }
        cg.saveGState()
        cg.addRect(bounds)
        for hole in holes {
            let radius = min(10, min(hole.width, hole.height) / 4)
            cg.addPath(StyledCanvasRenderer.roundedPath(hole, radius: radius))
        }
        cg.setFillColor(NSColor.black.withAlphaComponent(spotlightVeilAlpha).cgColor)
        cg.fillPath(using: .evenOdd)
        cg.restoreGState()
    }
}

/// Bounded cache of processed blur/pixelate regions for the live canvas.
@MainActor
final class PixelCache {
    static let shared = PixelCache()
    static let ciContext = CIContext(options: [.cacheIntermediates: false])
    private static let capacity = 24

    private var entries: [String: CGImage] = [:]
    private var order: [String] = []

    static func key(tool: AnnotationTool, rect: CGRect, source: CGImage) -> String {
        let id = ObjectIdentifier(source).hashValue
        return "\(tool.rawValue)|\(id)|\(source.width)x\(source.height)|\(Int(rect.minX)),\(Int(rect.minY)),\(Int(rect.width)),\(Int(rect.height))"
    }

    func image(for key: String) -> CGImage? { entries[key] }

    /// Called whenever a session adopts a new source image, so a recycled
    /// object address can never serve another image's pixels.
    func removeAll() {
        entries.removeAll()
        order.removeAll()
    }

    func store(_ image: CGImage, for key: String) {
        if entries[key] == nil { order.append(key) }
        entries[key] = image
        while order.count > Self.capacity {
            entries.removeValue(forKey: order.removeFirst())
        }
    }
}
