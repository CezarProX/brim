// AnnotationRenderer+Shapes.swift
// Brim
//
// Vector tools added for the screenshot editor window: curved arrow,
// ellipse (outline or filled) and the numbered step badge.

import AppKit

extension AnnotationRenderer {

    // MARK: - Curved arrow

    static func drawCurvedArrow(_ annotation: Annotation) {
        let p = annotation.points
        guard p.count == 3 else { return }
        let shaft = NSBezierPath()
        shaft.move(to: p[0])
        // Quadratic -> cubic: both cubic controls sit 2/3 of the way to the quad control.
        let c1 = CGPoint(x: p[0].x + 2 / 3 * (p[1].x - p[0].x), y: p[0].y + 2 / 3 * (p[1].y - p[0].y))
        let c2 = CGPoint(x: p[2].x + 2 / 3 * (p[1].x - p[2].x), y: p[2].y + 2 / 3 * (p[1].y - p[2].y))
        shaft.curve(to: p[2], controlPoint1: c1, controlPoint2: c2)
        shaft.lineWidth = annotation.style.lineWidth
        shaft.lineCapStyle = .round
        annotation.style.color.setStroke()
        shaft.stroke()
        // The head follows the curve's tangent at its end (control -> end).
        let angle = atan2(p[2].y - p[1].y, p[2].x - p[1].x)
        drawArrowHead(at: p[2], angle: angle, style: annotation.style)
    }

    // MARK: - Ellipse

    static func drawEllipse(_ annotation: Annotation) {
        let rect = annotation.rect.standardized
        guard rect.width > 0 || rect.height > 0 else { return }
        let path = NSBezierPath(ovalIn: rect)
        if annotation.style.isFilled {
            annotation.style.color.setFill()
            path.fill()
        } else {
            path.lineWidth = annotation.style.lineWidth
            annotation.style.color.setStroke()
            path.stroke()
        }
    }

    // MARK: - Step counter

    static func drawCounter(_ annotation: Annotation) {
        let rect = annotation.rect.standardized
        guard rect.width > 0 else { return }
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
        shadow.shadowBlurRadius = rect.width * 0.12
        shadow.shadowOffset = NSSize(width: 0, height: -rect.width * 0.05)
        shadow.set()
        annotation.style.color.setFill()
        NSBezierPath(ovalIn: rect).fill()
        NSGraphicsContext.restoreGraphicsState()

        let ring = NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1))
        ring.lineWidth = max(1.5, rect.width * 0.06)
        NSColor.white.withAlphaComponent(0.9).setStroke()
        ring.stroke()

        let label = annotation.text.isEmpty ? "1" : annotation.text
        let font = NSFont.systemFont(ofSize: rect.height * (label.count > 1 ? 0.46 : 0.55), weight: .bold)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: counterTextColor(on: annotation.style.color)]
        let size = (label as NSString).size(withAttributes: attributes)
        (label as NSString).draw(
            at: CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2),
            withAttributes: attributes
        )
    }

    /// White on dark/saturated badges, near-black on light ones (yellow, white).
    static func counterTextColor(on fill: NSColor) -> NSColor {
        guard let rgb = fill.usingColorSpace(.deviceRGB) else { return .white }
        let luminance = 0.299 * rgb.redComponent + 0.587 * rgb.greenComponent + 0.114 * rgb.blueComponent
        return luminance > 0.72 ? NSColor(white: 0.1, alpha: 1) : .white
    }
}
