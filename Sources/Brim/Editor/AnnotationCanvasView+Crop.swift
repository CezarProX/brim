// AnnotationCanvasView+Crop.swift
// Brim
//
// The crop tool. While it is active the host shows the whole, uncropped
// image; dragging draws the new crop frame, and releasing commits it as one
// undoable document entry (`EditorSession.setCrop`) and returns to the
// selection tool so the host can show the cropped result.

import AppKit

extension AnnotationCanvasView {

    func beginCropDraft(at point: CGPoint) {
        draftStart = point
        cropDraft = CGRect(origin: clampedToBounds(point), size: .zero)
        needsDisplay = true
    }

    func continueCropDraft(at point: CGPoint) {
        guard let start = draftStart else { return }
        cropDraft = Self.rectBetween(clampedToBounds(start), clampedToBounds(point))
        needsDisplay = true
    }

    func endCropDraft(at point: CGPoint) {
        continueCropDraft(at: point)
        let rect = cropDraft
        draftStart = nil
        cropDraft = nil
        needsDisplay = true
        guard let rect, rect.width >= 4, rect.height >= 4 else { return }
        session.setCrop(rect)
        session.currentTool = nil
    }

    private func clampedToBounds(_ point: CGPoint) -> CGPoint {
        CGPoint(x: min(max(point.x, bounds.minX), bounds.maxX), y: min(max(point.y, bounds.minY), bounds.maxY))
    }

    /// Dims everything outside the crop frame and draws the frame with a
    /// rule-of-thirds grid, only while the crop tool is active.
    func drawCropOverlay() {
        guard session.currentTool == .crop, let frame = cropDraft ?? session.cropRect else { return }
        let veil = NSBezierPath(rect: bounds)
        veil.append(NSBezierPath(rect: frame))
        veil.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.5).setFill()
        veil.fill()

        let unit = max(1, bounds.width / 600)
        let border = NSBezierPath(rect: frame)
        border.lineWidth = 1.5 * unit
        NSColor.white.setStroke()
        border.stroke()

        let grid = NSBezierPath()
        for i in 1...2 {
            let x = frame.minX + frame.width * CGFloat(i) / 3
            let y = frame.minY + frame.height * CGFloat(i) / 3
            grid.move(to: CGPoint(x: x, y: frame.minY)); grid.line(to: CGPoint(x: x, y: frame.maxY))
            grid.move(to: CGPoint(x: frame.minX, y: y)); grid.line(to: CGPoint(x: frame.maxX, y: y))
        }
        grid.lineWidth = 0.75 * unit
        NSColor.white.withAlphaComponent(0.45).setStroke()
        grid.stroke()
        drawCropCorners(frame, unit: unit)
    }

    private func drawCropCorners(_ frame: CGRect, unit: CGFloat) {
        let length = min(18 * unit, frame.width / 3, frame.height / 3)
        let corners = NSBezierPath()
        for (corner, dx, dy) in [
            (CGPoint(x: frame.minX, y: frame.minY), 1.0, 1.0), (CGPoint(x: frame.maxX, y: frame.minY), -1.0, 1.0),
            (CGPoint(x: frame.minX, y: frame.maxY), 1.0, -1.0), (CGPoint(x: frame.maxX, y: frame.maxY), -1.0, -1.0)
        ] {
            corners.move(to: CGPoint(x: corner.x + dx * length, y: corner.y))
            corners.line(to: corner)
            corners.line(to: CGPoint(x: corner.x, y: corner.y + dy * length))
        }
        corners.lineWidth = 4 * unit
        corners.lineCapStyle = .square
        NSColor.white.setStroke()
        corners.stroke()
    }
}
