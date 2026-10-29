// AnnotationCanvasView+Drafting.swift
// Brim
//
// In-progress annotation state for the drawing tools (everything but
// selection mode, the text tool and crop, which have their own files). Each
// tool is committed as a single undo step on mouseUp rather than on every
// intermediate mouseDragged event.

import AppKit

extension AnnotationCanvasView {

    // MARK: - Freehand (pen, highlighter)

    func beginPenStroke(at point: CGPoint) {
        draftPenPoints = [point]
        needsDisplay = true
    }

    func continuePenStroke(at point: CGPoint) {
        guard let last = draftPenPoints.last else { return }
        // Throttle sampling so slow, dense mouse events don't produce a
        // point cloud with no visual benefit.
        if hypot(point.x - last.x, point.y - last.y) > 1 {
            draftPenPoints.append(point)
            needsDisplay = true
        }
    }

    func commitPenStroke(tool: AnnotationTool = .pen) {
        defer {
            draftPenPoints = []
            needsDisplay = true
        }
        guard draftPenPoints.count > 1 else { return }
        // A 2-point highlighter would draw as a straight marker; give a
        // barely-moved freehand stroke a third sample so it stays freehand.
        var points = draftPenPoints
        if tool == .highlighter, points.count == 2 { points.insert(points[0], at: 1) }
        session.addAnnotation(Annotation(tool: tool, points: points, style: session.currentStyle))
    }

    // MARK: - Rubber-band shapes

    func beginShapeDraft(at point: CGPoint) {
        draftStart = point
        draftCurrent = point
        needsDisplay = true
    }

    func continueShapeDraft(at point: CGPoint) {
        draftCurrent = point
        needsDisplay = true
    }

    func commitShapeDraft(tool: AnnotationTool) {
        defer {
            draftStart = nil
            draftCurrent = nil
            needsDisplay = true
        }
        guard let start = draftStart, let end = draftCurrent, start != end,
              let annotation = Self.shape(tool: tool, from: start, to: end, style: session.currentStyle) else { return }
        session.addAnnotation(annotation)
    }

    /// The annotation a drag from `start` to `end` produces for `tool`.
    static func shape(tool: AnnotationTool, from start: CGPoint, to end: CGPoint, style: AnnotationStyle) -> Annotation? {
        switch tool {
        case .line, .arrow:
            return Annotation(tool: tool, points: [start, end], style: style)
        case .curvedArrow:
            let control = AnnotationGeometry.defaultControlPoint(from: start, to: end)
            return Annotation(tool: tool, points: [start, control, end], style: style)
        case .magnifier:
            return Annotation(tool: tool, rect: squareRect(from: start, to: end), style: style)
        case .rectangle, .ellipse, .blur, .pixelate, .spotlight:
            return Annotation(tool: tool, rect: rectBetween(start, end), style: style)
        case .pen, .highlighter, .text, .counter, .crop:
            return nil
        }
    }

    static func rectBetween(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    /// A lens grows as a square from the drag start, following the drag direction.
    static func squareRect(from start: CGPoint, to end: CGPoint) -> CGRect {
        let side = max(abs(end.x - start.x), abs(end.y - start.y))
        let x = end.x >= start.x ? start.x : start.x - side
        let y = end.y >= start.y ? start.y : start.y - side
        return CGRect(x: x, y: y, width: side, height: side)
    }

    func rect(from a: CGPoint, to b: CGPoint) -> CGRect { Self.rectBetween(a, b) }

    // MARK: - Step counter

    func placeCounter(at point: CGPoint) {
        let number = AnnotationGeometry.nextCounterNumber(in: session.document.annotations)
        let rect = AnnotationGeometry.counterRect(centeredAt: point, lineWidth: session.currentStyle.lineWidth)
        session.addAnnotation(Annotation(tool: .counter, rect: rect, text: "\(number)", style: session.currentStyle))
    }

    // MARK: - Draft preview

    /// The in-progress stroke or shape, drawn with the live `currentStyle`
    /// so style changes show immediately.
    func draftAnnotations() -> [Annotation] {
        if draftPenPoints.count > 1 {
            let tool: AnnotationTool = session.currentTool == .highlighter ? .highlighter : .pen
            var points = draftPenPoints
            if tool == .highlighter, points.count == 2 { points.insert(points[0], at: 1) }
            return [Annotation(tool: tool, points: points, style: session.currentStyle)]
        }
        guard let start = draftStart, let end = draftCurrent, let tool = session.currentTool,
              let shape = Self.shape(tool: tool, from: start, to: end, style: session.currentStyle) else { return [] }
        return [shape]
    }
}
