// AnnotationRenderContext.swift
// Brim
//
// What the pixel-reading tools (blur, pixelate, magnifier) and the
// spotlight veil need beyond the annotation itself: the screenshot's pixels,
// where that screenshot sits in canvas coordinates, and the visible canvas
// bounds. Without a source (the in-place capture overlay) those tools fall
// back to a neutral frosted placeholder.

import AppKit

struct AnnotationRenderContext {
    /// The screenshot pixels the annotations sit on, if available.
    var source: CGImage?
    /// The rect, in canvas coordinates, the whole `source` image covers.
    var sourceFrame: CGRect
    /// The visible canvas area (the spotlight veil covers exactly this).
    var canvasBounds: CGRect
    /// The live canvas caches processed regions; one-off exports do not.
    var usesCache = false

    static let empty = AnnotationRenderContext(source: nil, sourceFrame: .zero, canvasBounds: .zero)

    /// Maps a canvas-space rect onto `source`'s pixel grid (CGImage space,
    /// top-left origin), clamped to the image. Nil when nothing overlaps.
    func sourcePixelRect(for rect: CGRect) -> CGRect? {
        guard let source, sourceFrame.width > 0, sourceFrame.height > 0 else { return nil }
        let sx = CGFloat(source.width) / sourceFrame.width
        let sy = CGFloat(source.height) / sourceFrame.height
        let r = rect.standardized
        let pixel = CGRect(
            x: (r.minX - sourceFrame.minX) * sx,
            y: (sourceFrame.maxY - r.maxY) * sy,
            width: r.width * sx,
            height: r.height * sy
        ).integral
        let clamped = pixel.intersection(CGRect(x: 0, y: 0, width: source.width, height: source.height))
        return clamped.isNull || clamped.width < 1 || clamped.height < 1 ? nil : clamped
    }

    /// The canvas-space rect a pixel rect from `sourcePixelRect` covers.
    func canvasRect(forPixelRect pixel: CGRect) -> CGRect {
        guard let source, source.width > 0, source.height > 0 else { return .zero }
        let sx = sourceFrame.width / CGFloat(source.width)
        let sy = sourceFrame.height / CGFloat(source.height)
        return CGRect(
            x: sourceFrame.minX + pixel.minX * sx,
            y: sourceFrame.maxY - pixel.maxY * sy,
            width: pixel.width * sx,
            height: pixel.height * sy
        )
    }

    /// Source pixels per canvas point (1 when there is no source).
    var pixelScale: CGFloat {
        guard let source, sourceFrame.width > 0 else { return 1 }
        return CGFloat(source.width) / sourceFrame.width
    }
}
