// StudioBackdrop.swift
// Brim
//
// Draws the canvas background behind a recording. Kept behind a small protocol so the editor can
// switch to the shared screenshot-styling renderer (Editor/Styling) once that lands, without
// touching the compositor: assign `StudioBackdrop.renderer` to an adapter and everything follows.

import CoreGraphics
import Foundation

protocol StudioBackdropRendering: Sendable {
    /// A full-bleed image of `background` at exactly `size` pixels.
    func image(for background: StudioBackground, size: CGSize) -> CGImage?
}

enum StudioBackdrop {
    nonisolated(unsafe) static var renderer: any StudioBackdropRendering = GradientBackdropRenderer()
}

/// The built-in renderer: angled multi-stop gradients with a soft light bloom, or a flat colour.
struct GradientBackdropRenderer: StudioBackdropRendering {
    func image(for background: StudioBackground, size: CGSize) -> CGImage? {
        let width = max(1, Int(size.width.rounded())), height = max(1, Int(size.height.rounded()))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        switch background {
        case .solid(let color):
            context.setFillColor(color.cgColor)
            context.fill(rect)
        case .gradient(let id):
            Self.drawGradient(StudioGradient.preset(id), in: rect, context: context, space: space)
        }
        return context.makeImage()
    }

    static func drawGradient(_ gradient: StudioGradient, in rect: CGRect, context: CGContext, space: CGColorSpace) {
        let colors = gradient.colors.map(\.cgColor) as CFArray
        let stops = gradient.colors.indices.map { CGFloat($0) / CGFloat(max(1, gradient.colors.count - 1)) }
        guard let linear = CGGradient(colorsSpace: space, colors: colors, locations: stops) else { return }
        // CoreGraphics' y axis points up; flip the angle so 90° runs top to bottom like the swatches.
        let radians = -gradient.angle * .pi / 180
        let half = hypot(rect.width, rect.height) / 2
        let dx = cos(radians) * half, dy = sin(radians) * half
        let start = CGPoint(x: rect.midX - dx, y: rect.midY - dy)
        let end = CGPoint(x: rect.midX + dx, y: rect.midY + dy)
        context.drawLinearGradient(linear, start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        // A gentle bloom from the upper left gives the flat gradient some depth.
        let bloomColors = [CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.22), CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0)] as CFArray
        if let bloom = CGGradient(colorsSpace: space, colors: bloomColors, locations: [0, 1]) {
            let center = CGPoint(x: rect.minX + rect.width * 0.22, y: rect.maxY - rect.height * 0.12)
            context.drawRadialGradient(bloom, startCenter: center, startRadius: 0, endCenter: center,
                                       endRadius: max(rect.width, rect.height) * 0.7, options: [])
        }
    }
}
