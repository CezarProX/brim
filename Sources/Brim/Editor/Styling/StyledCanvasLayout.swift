// StyledCanvasLayout.swift
// Brim
//
// Pure geometry for a styled canvas: given the content's size (points for a
// screenshot, pixels for a video frame -- the unit does not matter) and a
// `CanvasStyle`, where everything goes. All rects use a bottom-left origin.
//
//   padding  = style.padding * meanSide           meanSide = (w + h) / 2
//   radius   = corners.radiusFactor * sqrt(w * h), capped at half the short side
//   shadow   = blur radius style.shadow * 0.055 * sqrt(w * h)
//   canvas   = content + 2 * padding, then grown (never shrunk) along one axis
//              to match the aspect preset; spare room is distributed by the
//              alignment anchor.

import CoreGraphics

struct StyledCanvasLayout: Equatable, Sendable {
    let canvasSize: CGSize
    let contentRect: CGRect
    let cornerRadius: CGFloat
    /// 0 unless the style rounds the outer canvas.
    let outerCornerRadius: CGFloat
    let shadowBlur: CGFloat
    /// Offset of the shadow (negative y = below, bottom-left space).
    let shadowOffset: CGSize
    let shadowOpacity: CGFloat

    static func make(contentSize: CGSize, style: CanvasStyle) -> StyledCanvasLayout {
        let w = max(1, contentSize.width), h = max(1, contentSize.height)
        guard style.isEnabled else {
            return StyledCanvasLayout(
                canvasSize: CGSize(width: w, height: h), contentRect: CGRect(x: 0, y: 0, width: w, height: h),
                cornerRadius: 0, outerCornerRadius: 0, shadowBlur: 0, shadowOffset: .zero, shadowOpacity: 0
            )
        }
        let geometricSide = (w * h).squareRoot()
        let pad = CGFloat(min(CanvasStyle.maxPadding, max(0, style.padding))) * (w + h) / 2
        let canvas = canvasSize(content: CGSize(width: w, height: h), padding: pad, ratio: style.aspect.ratio)
        let spare = CGSize(width: canvas.width - w - 2 * pad, height: canvas.height - h - 2 * pad)
        let anchor = style.alignment.anchor
        let content = CGRect(x: pad + spare.width * anchor.x, y: pad + spare.height * anchor.y, width: w, height: h)

        let radius = min(style.corners.radiusFactor * geometricSide, min(w, h) / 2)
        let strength = CGFloat(min(1, max(0, style.shadow)))
        let blur = strength * 0.055 * geometricSide
        let outer = style.roundsOuterCorners
            ? min(min(canvas.width, canvas.height) / 2, radius + pad * 0.5 + 0.012 * geometricSide)
            : 0
        return StyledCanvasLayout(
            canvasSize: canvas, contentRect: content, cornerRadius: radius, outerCornerRadius: outer,
            shadowBlur: blur, shadowOffset: CGSize(width: 0, height: -blur * 0.35),
            shadowOpacity: strength > 0 ? 0.25 + 0.4 * strength : 0
        )
    }

    /// Smallest canvas with the requested ratio that holds the padded content.
    static func canvasSize(content: CGSize, padding: CGFloat, ratio: CGFloat?) -> CGSize {
        let inner = CGSize(width: content.width + 2 * padding, height: content.height + 2 * padding)
        guard let ratio, ratio > 0 else { return inner }
        if inner.width / inner.height < ratio {
            return CGSize(width: inner.height * ratio, height: inner.height)
        }
        return CGSize(width: inner.width, height: inner.width / ratio)
    }

    /// The same layout in another unit (e.g. points -> pixels).
    func scaled(by factor: CGFloat) -> StyledCanvasLayout {
        StyledCanvasLayout(
            canvasSize: CGSize(width: canvasSize.width * factor, height: canvasSize.height * factor),
            contentRect: CGRect(x: contentRect.minX * factor, y: contentRect.minY * factor,
                                width: contentRect.width * factor, height: contentRect.height * factor),
            cornerRadius: cornerRadius * factor, outerCornerRadius: outerCornerRadius * factor,
            shadowBlur: shadowBlur * factor,
            shadowOffset: CGSize(width: shadowOffset.width * factor, height: shadowOffset.height * factor),
            shadowOpacity: shadowOpacity
        )
    }
}
