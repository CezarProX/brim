// AnnotationRenderer.swift
// Brim
//
// Shared drawing core used by BOTH the live `AnnotationCanvasView` (drawing
// straight into the current `NSGraphicsContext` during `draw(_:)`) and
// `EditorSession.render(over:canvasSize:)` (drawing into an offscreen
// `NSBitmapImageRep` for the flattened export). Keeping a single drawing
// implementation guarantees what the user sees while editing matches what
// gets exported.
//
// All coordinates are in canvas points, origin bottom-left (AppKit's default
// non-flipped coordinate space), matching `Annotation.points` / `.rect`.

import AppKit

@MainActor
enum AnnotationRenderer {

    /// Draws every annotation, in order, into the current graphics context.
    /// The spotlight veil is drawn once, at the first spotlight's position in
    /// the stacking order, with a hole for every spotlight.
    static func drawAll(_ annotations: [Annotation], context: AnnotationRenderContext = .empty) {
        var drewVeil = false
        for annotation in annotations {
            if annotation.tool == .spotlight {
                guard !drewVeil else { continue }
                drewVeil = true
                drawSpotlightVeil(annotations.filter { $0.tool == .spotlight }, context: context)
                continue
            }
            draw(annotation, context: context)
        }
    }

    /// Draws a single annotation into the current graphics context.
    static func draw(_ annotation: Annotation, context: AnnotationRenderContext = .empty) {
        switch annotation.tool {
        case .pen:
            drawPen(annotation)
        case .line:
            drawLine(annotation)
        case .arrow:
            drawArrow(annotation)
        case .rectangle:
            drawRectangle(annotation)
        case .highlighter:
            drawHighlighter(annotation)
        case .text:
            drawText(annotation)
        case .curvedArrow:
            drawCurvedArrow(annotation)
        case .ellipse:
            drawEllipse(annotation)
        case .counter:
            drawCounter(annotation)
        case .blur, .pixelate:
            drawObscured(annotation, context: context)
        case .magnifier:
            drawMagnifier(annotation, context: context)
        case .spotlight:
            drawSpotlightVeil([annotation], context: context)
        case .crop:
            break
        }
    }

    // MARK: - Pen

    private static func drawPen(_ annotation: Annotation) {
        guard annotation.points.count > 1 else { return }
        let path = smoothPath(through: annotation.points)
        path.lineWidth = annotation.style.lineWidth
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        annotation.style.color.setStroke()
        path.stroke()
    }

    /// Builds a smoothed freehand path by curving through the midpoints of
    /// consecutive samples, which removes the "faceted" look of a plain
    /// polyline without needing a heavier curve-fitting algorithm.
    static func smoothPath(through points: [CGPoint]) -> NSBezierPath {
        let path = NSBezierPath()
        guard let first = points.first else { return path }

        if points.count < 3 {
            path.move(to: first)
            if let last = points.last {
                path.line(to: last)
            }
            return path
        }

        path.move(to: first)
        var previousMid = first
        for index in 1..<(points.count - 1) {
            let current = points[index]
            let next = points[index + 1]
            let mid = CGPoint(x: (current.x + next.x) / 2, y: (current.y + next.y) / 2)
            path.curve(to: mid, controlPoint1: previousMid, controlPoint2: current)
            previousMid = mid
        }
        path.line(to: points[points.count - 1])
        return path
    }

    // MARK: - Line

    private static func drawLine(_ annotation: Annotation) {
        guard annotation.points.count >= 2 else { return }
        let path = NSBezierPath()
        path.lineWidth = annotation.style.lineWidth
        path.lineCapStyle = .round
        path.move(to: annotation.points[0])
        path.line(to: annotation.points[1])
        annotation.style.color.setStroke()
        path.stroke()
    }

    // MARK: - Arrow

    private static func drawArrow(_ annotation: Annotation) {
        guard annotation.points.count >= 2 else { return }
        let start = annotation.points[0]
        let end = annotation.points[1]

        let shaft = NSBezierPath()
        shaft.lineWidth = annotation.style.lineWidth
        shaft.lineCapStyle = .round
        shaft.move(to: start)
        shaft.line(to: end)
        annotation.style.color.setStroke()
        shaft.stroke()

        drawArrowHead(at: end, angle: atan2(end.y - start.y, end.x - start.x), style: annotation.style)
    }

    /// A filled triangular head whose tip is `tip`, pointing along `angle`.
    static func drawArrowHead(at tip: CGPoint, angle: CGFloat, style: AnnotationStyle) {
        let headLength = max(10, style.lineWidth * 4)
        let headAngle: CGFloat = .pi / 7
        let wing1 = CGPoint(
            x: tip.x - headLength * cos(angle - headAngle),
            y: tip.y - headLength * sin(angle - headAngle)
        )
        let wing2 = CGPoint(
            x: tip.x - headLength * cos(angle + headAngle),
            y: tip.y - headLength * sin(angle + headAngle)
        )
        let head = NSBezierPath()
        head.move(to: tip)
        head.line(to: wing1)
        head.line(to: wing2)
        head.close()
        style.color.setFill()
        head.fill()
    }

    // MARK: - Rectangle

    private static func drawRectangle(_ annotation: Annotation) {
        guard annotation.rect.width > 0 || annotation.rect.height > 0 else { return }
        let path = NSBezierPath(roundedRect: annotation.rect, xRadius: 2, yRadius: 2)
        if annotation.style.isFilled {
            annotation.style.color.setFill()
            path.fill()
            return
        }
        path.lineWidth = annotation.style.lineWidth
        annotation.style.color.setStroke()
        path.stroke()
    }

    // MARK: - Highlighter

    /// Two points draw a straight marker stroke (the original behaviour);
    /// more points draw a smoothed freehand stroke.
    private static func drawHighlighter(_ annotation: Annotation) {
        guard annotation.points.count >= 2 else { return }
        let path: NSBezierPath
        if annotation.points.count == 2 {
            path = NSBezierPath()
            path.move(to: annotation.points[0])
            path.line(to: annotation.points[1])
        } else {
            path = smoothPath(through: annotation.points)
        }
        path.lineWidth = annotation.style.lineWidth * 4
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        annotation.style.color.withAlphaComponent(0.35).setStroke()
        path.stroke()
    }

    // MARK: - Text

    private static func drawText(_ annotation: Annotation) {
        guard !annotation.text.isEmpty else { return }
        let font = NSFont.systemFont(ofSize: annotation.style.fontSize, weight: .medium)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: annotation.style.color
        ]
        annotation.text.draw(at: annotation.rect.origin, withAttributes: attributes)
    }

    /// Measures the on-canvas bounding size a text annotation would occupy,
    /// used for hit-testing and for sizing the inline edit field.
    static func textSize(for annotation: Annotation) -> CGSize {
        let font = NSFont.systemFont(ofSize: annotation.style.fontSize, weight: .medium)
        let measured = (annotation.text as NSString).size(withAttributes: [.font: font])
        return CGSize(
            width: max(measured.width, 10),
            height: max(measured.height, annotation.style.fontSize)
        )
    }

    // MARK: - Flattened export

    /// Renders `annotations` over `image`, returning a new flattened image
    /// that preserves `image`'s pixel resolution (retina fidelity) while
    /// keeping its original point size. `canvasSize` is the point size the
    /// annotations were authored against (the live canvas view's bounds),
    /// used to scale annotation coordinates onto the image's pixel grid.
    static func render(_ annotations: [Annotation], over image: NSImage, canvasSize: CGSize) -> NSImage {
        let pixelSize = pixelDimensions(of: image)
        let pixelsWide = max(1, Int(pixelSize.width.rounded()))
        let pixelsHigh = max(1, Int(pixelSize.height.rounded()))

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelsWide,
            pixelsHigh: pixelsHigh,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return image
        }
        // IMPORTANT: leave `rep.size` at its default (== pixel dimensions)
        // until AFTER drawing. `NSGraphicsContext(bitmapImageRep:)` derives
        // its user space from `rep.size`; setting the point size first makes
        // user-space units points while the draw rects below are in pixels,
        // which blows the image up 2x and exports only its bottom-left
        // quadrant on Retina.
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
            return image
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context

        image.draw(
            in: CGRect(origin: .zero, size: CGSize(width: pixelsWide, height: pixelsHigh)),
            from: .zero,
            operation: .copy,
            fraction: 1.0
        )

        let scaleX = canvasSize.width > 0 ? CGFloat(pixelsWide) / canvasSize.width : 1
        let scaleY = canvasSize.height > 0 ? CGFloat(pixelsHigh) / canvasSize.height : 1

        let renderContext = AnnotationRenderContext(
            source: image.cgImage(forProposedRect: nil, context: nil, hints: nil),
            sourceFrame: CGRect(origin: .zero, size: canvasSize),
            canvasBounds: CGRect(origin: .zero, size: canvasSize)
        )
        context.cgContext.saveGState()
        context.cgContext.scaleBy(x: scaleX, y: scaleY)
        drawAll(annotations, context: renderContext)
        context.cgContext.restoreGState()

        NSGraphicsContext.current?.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        // Now that drawing is done, stamp the logical point size so the
        // flattened image keeps the original's on-screen dimensions.
        rep.size = image.size

        let output = NSImage(size: image.size)
        output.addRepresentation(rep)
        return output
    }

    private static func pixelDimensions(of image: NSImage) -> CGSize {
        if let rep = image.representations.first {
            return CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        }
        return image.size
    }
}
