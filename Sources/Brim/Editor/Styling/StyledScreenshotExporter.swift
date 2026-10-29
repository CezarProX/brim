// StyledScreenshotExporter.swift
// Brim
//
// Flattens an editor session into the final image: annotations over the
// screenshot (at the screenshot's native pixel density), then the crop,
// then the styled background. The output keeps the source's pixels-per-point
// so a Retina capture exports as a Retina image.

import AppKit

@MainActor
enum StyledScreenshotExporter {

    /// - Parameters:
    ///   - image: the original screenshot; annotation coordinates are its points.
    ///   - annotations: the session's document (a crop entry, if any, is honoured).
    static func render(image: NSImage, annotations: [Annotation], style: CanvasStyle) -> NSImage {
        let marks = annotations.filter { $0.tool != .crop }
        let annotated = marks.isEmpty ? image : AnnotationRenderer.render(marks, over: image, canvasSize: image.size)
        guard let source = annotated.cgImage(forProposedRect: nil, context: nil, hints: nil),
              image.size.width > 0 else { return annotated }
        let scale = CGFloat(source.width) / image.size.width
        let crop = AnnotationGeometry.crop(in: annotations)?.rect
        let (content, contentSize) = cropped(source, to: crop, imageSize: image.size, scale: scale)
        guard style.isEnabled else {
            return NSImage(cgImage: content, size: contentSize)
        }
        let background = BackgroundResolver.resolve(style.background)
        guard let output = StyledCanvasRenderer.render(
            content: content, contentSize: contentSize, style: style, background: background, scale: scale
        ) else { return NSImage(cgImage: content, size: contentSize) }
        let canvas = StyledCanvasLayout.make(contentSize: contentSize, style: style).canvasSize
        return NSImage(cgImage: output, size: canvas)
    }

    /// Applies a crop given in image points (bottom-left origin).
    static func cropped(_ source: CGImage, to crop: CGRect?, imageSize: CGSize, scale: CGFloat) -> (CGImage, CGSize) {
        guard let crop = crop?.standardized.intersection(CGRect(origin: .zero, size: imageSize)),
              !crop.isNull, crop.width >= 1, crop.height >= 1 else {
            return (source, imageSize)
        }
        let pixelRect = CGRect(
            x: crop.minX * scale,
            y: (imageSize.height - crop.maxY) * scale,
            width: crop.width * scale,
            height: crop.height * scale
        ).integral
        guard let result = source.cropping(to: pixelRect) else { return (source, imageSize) }
        return (result, CGSize(width: CGFloat(result.width) / scale, height: CGFloat(result.height) / scale))
    }
}
