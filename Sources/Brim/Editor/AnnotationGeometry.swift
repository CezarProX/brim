// AnnotationGeometry.swift
// Brim
//
// Pure, view-independent geometry for annotations: translation, bounding
// boxes, curved-arrow control points and step-counter numbering. Shared by
// the canvas (hit-testing, selection outline, drag previews) and by tests.

import AppKit

@MainActor
enum AnnotationGeometry {

    /// Tools whose geometry is a rectangle in `rect`.
    static func isRectBased(_ tool: AnnotationTool) -> Bool {
        switch tool {
        case .rectangle, .ellipse, .blur, .pixelate, .spotlight, .magnifier, .counter, .crop, .text:
            return true
        case .pen, .line, .arrow, .highlighter, .curvedArrow:
            return false
        }
    }

    /// A copy of `annotation` moved by `offset`.
    static func translated(_ annotation: Annotation, by offset: CGSize) -> Annotation {
        guard offset != .zero else { return annotation }
        if isRectBased(annotation.tool) {
            return annotation.with(rect: annotation.rect.offsetBy(dx: offset.width, dy: offset.height))
        }
        let points = annotation.points.map { CGPoint(x: $0.x + offset.width, y: $0.y + offset.height) }
        return annotation.with(points: points)
    }

    /// The axis-aligned box an annotation visibly occupies (before outline padding).
    static func bounds(of annotation: Annotation) -> CGRect {
        switch annotation.tool {
        case .text:
            return CGRect(origin: annotation.rect.origin, size: AnnotationRenderer.textSize(for: annotation))
        case .curvedArrow:
            return pointsBounds(curveSamples(annotation.points))
        default:
            if isRectBased(annotation.tool) { return annotation.rect.standardized }
            return pointsBounds(annotation.points)
        }
    }

    static func pointsBounds(_ points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return .zero }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for point in points.dropFirst() {
            minX = min(minX, point.x); maxX = max(maxX, point.x)
            minY = min(minY, point.y); maxY = max(maxY, point.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    // MARK: - Curved arrow

    /// The default bend for a freshly drawn curved arrow: the control point
    /// sits off the chord's midpoint by a quarter of its length, to the left
    /// of the drawing direction, so a left-to-right drag arcs upward.
    static func defaultControlPoint(from start: CGPoint, to end: CGPoint) -> CGPoint {
        let mid = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        let dx = end.x - start.x, dy = end.y - start.y
        let length = hypot(dx, dy)
        guard length > 0 else { return mid }
        let bend = length * 0.25
        return CGPoint(x: mid.x - dy / length * bend, y: mid.y + dx / length * bend)
    }

    /// Point on the quadratic curve [start, control, end] at `t`.
    static func quadPoint(_ p: [CGPoint], t: CGFloat) -> CGPoint {
        guard p.count >= 3 else { return p.first ?? .zero }
        let u = 1 - t
        return CGPoint(
            x: u * u * p[0].x + 2 * u * t * p[1].x + t * t * p[2].x,
            y: u * u * p[0].y + 2 * u * t * p[1].y + t * t * p[2].y
        )
    }

    /// Polyline approximation of a curved arrow (or the points unchanged
    /// for anything that is not a three-point curve), for hit-testing.
    static func curveSamples(_ points: [CGPoint], steps: Int = 24) -> [CGPoint] {
        guard points.count == 3 else { return points }
        return (0...steps).map { quadPoint(points, t: CGFloat($0) / CGFloat(steps)) }
    }

    // MARK: - Step counter

    /// Badge diameter for a counter drawn with `lineWidth`.
    static func counterDiameter(lineWidth: CGFloat) -> CGFloat {
        max(22, 16 + lineWidth * 4)
    }

    /// Badge rect centred on `point`.
    static func counterRect(centeredAt point: CGPoint, lineWidth: CGFloat) -> CGRect {
        let d = counterDiameter(lineWidth: lineWidth)
        return CGRect(x: point.x - d / 2, y: point.y - d / 2, width: d, height: d)
    }

    /// The number the next step badge should show: one past the highest
    /// existing badge, so deleting step 2 of 3 does not renumber 3.
    static func nextCounterNumber(in annotations: [Annotation]) -> Int {
        let numbers = annotations.filter { $0.tool == .counter }.compactMap { Int($0.text) }
        return (numbers.max() ?? 0) + 1
    }

    /// The document's crop entry, if any.
    static func crop(in annotations: [Annotation]) -> Annotation? {
        annotations.last { $0.tool == .crop }
    }
}
