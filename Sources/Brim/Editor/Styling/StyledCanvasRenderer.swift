// StyledCanvasRenderer.swift
// Brim
//
// Draws a styled canvas with CoreGraphics. It is independent of images and
// of the screenshot editor, so it can be reused for video frames.
//
// Reuse (screenshots, video frames, thumbnails):
//
//   let layout = StyledCanvasLayout.make(contentSize: frameSize, style: style)
//       .scaled(by: pixelsPerUnit)                       // work in device pixels
//   let background = BackgroundResolver.resolve(style.background)   // once, not per frame
//   StyledCanvasRenderer.drawBackdrop(in: ctx, layout: layout, background: background)
//   StyledCanvasRenderer.drawContent(in: ctx, layout: layout) { ctx, rect in
//       ctx.draw(frameImage, in: rect)                   // clipped to the rounded frame
//   }
//
// or, for a single still: `StyledCanvasRenderer.render(content:contentSize:style:background:scale:)`.
//
// Contract: `ctx` must have an identity (or translation-only) CTM in device
// pixels with a bottom-left origin, because CoreGraphics shadows ignore the
// CTM. The backdrop is constant for a given layout, so a video pipeline can
// render it once (`renderBackdrop`) and composite each frame over it.

import CoreGraphics
import Foundation

/// A background ready to draw (images already loaded and blurred).
enum ResolvedBackground {
    case none
    case solid(CGColor)
    case gradient(GradientPreset)
    case image(CGImage)
}

enum StyledCanvasRenderer {

    // MARK: - Building blocks

    /// Fills the canvas with the background (clipped to the rounded outer
    /// canvas when the style asks for it) and casts the content's shadow.
    static func drawBackdrop(in ctx: CGContext, layout: StyledCanvasLayout, background: ResolvedBackground) {
        let canvas = CGRect(origin: .zero, size: layout.canvasSize)
        ctx.saveGState()
        if layout.outerCornerRadius > 0 {
            ctx.addPath(roundedPath(canvas, radius: layout.outerCornerRadius))
            ctx.clip()
        }
        drawBackground(background, in: ctx, rect: canvas)
        drawShadow(in: ctx, layout: layout)
        ctx.restoreGState()
    }

    /// Clips to the rounded content frame and lets `draw` paint the content
    /// into `layout.contentRect`.
    static func drawContent(in ctx: CGContext, layout: StyledCanvasLayout, draw: (CGContext, CGRect) -> Void) {
        ctx.saveGState()
        ctx.addPath(roundedPath(layout.contentRect, radius: layout.cornerRadius))
        ctx.clip()
        draw(ctx, layout.contentRect)
        ctx.restoreGState()
    }

    static func drawBackground(_ background: ResolvedBackground, in ctx: CGContext, rect: CGRect) {
        switch background {
        case .none:
            break
        case .solid(let color):
            ctx.setFillColor(color)
            ctx.fill(rect)
        case .gradient(let preset):
            drawGradient(preset, in: ctx, rect: rect)
        case .image(let image):
            ctx.saveGState()
            ctx.clip(to: rect)
            ctx.interpolationQuality = .high
            ctx.draw(image, in: aspectFill(CGSize(width: image.width, height: image.height), in: rect))
            ctx.restoreGState()
        }
    }

    /// Linear base gradient along `preset.angle`, then soft radial blobs.
    static func drawGradient(_ preset: GradientPreset, in ctx: CGContext, rect: CGRect) {
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let colors = preset.stops.map(\.cgColor) as CFArray
        let count = max(1, preset.stops.count - 1)
        let locations = (0...count).map { CGFloat($0) / CGFloat(count) }
        guard let base = CGGradient(colorsSpace: space, colors: colors, locations: locations) else { return }
        let radians = preset.angle * .pi / 180
        let direction = CGPoint(x: cos(radians), y: sin(radians))
        let half = (abs(rect.width * direction.x) + abs(rect.height * direction.y)) / 2
        let start = CGPoint(x: rect.midX - direction.x * half, y: rect.midY - direction.y * half)
        let end = CGPoint(x: rect.midX + direction.x * half, y: rect.midY + direction.y * half)
        ctx.saveGState()
        ctx.clip(to: rect)
        ctx.drawLinearGradient(base, start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        let longSide = max(rect.width, rect.height)
        for blob in preset.blobs {
            let blobColors = [blob.color.cgColor, blob.color.withAlpha(0).cgColor] as CFArray
            guard let radial = CGGradient(colorsSpace: space, colors: blobColors, locations: [0, 1]) else { continue }
            let center = CGPoint(x: rect.minX + blob.center.x * rect.width, y: rect.minY + blob.center.y * rect.height)
            ctx.drawRadialGradient(radial, startCenter: center, startRadius: 0,
                                   endCenter: center, endRadius: blob.radius * longSide, options: [])
        }
        ctx.restoreGState()
    }

    /// Casts only the shadow of the content frame: the silhouette is drawn
    /// far off-canvas and the shadow offset brings just its shadow back, so
    /// nothing opaque is painted under transparent content.
    static func drawShadow(in ctx: CGContext, layout: StyledCanvasLayout) {
        guard layout.shadowOpacity > 0, layout.shadowBlur > 0 else { return }
        let far = layout.canvasSize.width + layout.shadowBlur * 4 + 100
        ctx.saveGState()
        ctx.setShadow(
            offset: CGSize(width: layout.shadowOffset.width + far, height: layout.shadowOffset.height),
            blur: layout.shadowBlur,
            color: CGColor(gray: 0, alpha: layout.shadowOpacity)
        )
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        ctx.addPath(roundedPath(layout.contentRect.offsetBy(dx: -far, dy: 0), radius: layout.cornerRadius))
        ctx.fillPath()
        ctx.restoreGState()
    }

    // MARK: - One-shot rendering

    /// Renders backdrop + `content` at `scale` device pixels per layout unit.
    static func render(content: CGImage?, contentSize: CGSize, style: CanvasStyle,
                       background: ResolvedBackground, scale: CGFloat) -> CGImage? {
        let layout = StyledCanvasLayout.make(contentSize: contentSize, style: style).scaled(by: scale)
        guard let ctx = makeContext(size: layout.canvasSize) else { return nil }
        if style.isEnabled { drawBackdrop(in: ctx, layout: layout, background: background) }
        if let content {
            drawContent(in: ctx, layout: layout) { ctx, rect in
                ctx.interpolationQuality = .high
                ctx.draw(content, in: rect)
            }
        }
        return ctx.makeImage()
    }

    /// Just the backdrop (background + shadow), for live previews and for
    /// video pipelines that composite frames over a constant backdrop.
    static func renderBackdrop(layout: StyledCanvasLayout, background: ResolvedBackground) -> CGImage? {
        guard let ctx = makeContext(size: layout.canvasSize) else { return nil }
        drawBackdrop(in: ctx, layout: layout, background: background)
        return ctx.makeImage()
    }

    static func makeContext(size: CGSize) -> CGContext? {
        let width = max(1, Int(size.width.rounded())), height = max(1, Int(size.height.rounded()))
        return CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }

    // MARK: - Geometry helpers

    static func roundedPath(_ rect: CGRect, radius: CGFloat) -> CGPath {
        let r = min(radius, min(rect.width, rect.height) / 2)
        guard r > 0 else { return CGPath(rect: rect, transform: nil) }
        return CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)
    }

    /// The rect that scales `size` to cover `rect`, centred.
    static func aspectFill(_ size: CGSize, in rect: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0 else { return rect }
        let scale = max(rect.width / size.width, rect.height / size.height)
        let fitted = CGSize(width: size.width * scale, height: size.height * scale)
        return CGRect(x: rect.midX - fitted.width / 2, y: rect.midY - fitted.height / 2,
                      width: fitted.width, height: fitted.height)
    }
}
