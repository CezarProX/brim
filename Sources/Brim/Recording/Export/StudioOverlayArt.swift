// StudioOverlayArt.swift
// Brim
//
// Bitmaps the frame renderer composites: the rounded-frame mask, its drop shadow, the redrawn
// pointer (vector, so it stays crisp at any zoom) and the click ripple. All drawn with
// CoreGraphics in a bottom-left coordinate space to match Core Image.

import CoreGraphics
import CoreImage
import Foundation

enum StudioOverlayArt {
    static let sRGB = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    private static func rgbaContext(_ width: Int, _ height: Int) -> CGContext? {
        CGContext(data: nil, width: max(1, width), height: max(1, height), bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }

    /// White rounded rect on black, canvas sized. `frame` is in bottom-left (Core Image) space.
    static func mask(canvas: CGSize, frame: CGRect, radius: Double) -> CIImage {
        guard let context = CGContext(data: nil, width: Int(canvas.width), height: Int(canvas.height), bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return CIImage(color: .white).cropped(to: frame) }
        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(origin: .zero, size: canvas))
        context.setFillColor(gray: 1, alpha: 1)
        context.addPath(CGPath(roundedRect: frame, cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.fillPath()
        return context.makeImage().map { CIImage(cgImage: $0) } ?? CIImage(color: .white).cropped(to: frame)
    }

    /// The soft shadow under the frame (the frame itself is covered by the video).
    static func shadow(canvas: CGSize, frame: CGRect, layout: FrameLayout) -> CIImage? {
        guard layout.shadowOpacity > 0.001, let context = rgbaContext(Int(canvas.width), Int(canvas.height)) else { return nil }
        context.setShadow(offset: CGSize(width: 0, height: -layout.shadowOffset), blur: layout.shadowRadius,
                          color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: layout.shadowOpacity))
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        let inset = frame.insetBy(dx: 1, dy: 1)
        context.addPath(CGPath(roundedRect: inset, cornerWidth: layout.cornerRadius, cornerHeight: layout.cornerRadius, transform: nil))
        context.fillPath()
        return context.makeImage().map { CIImage(cgImage: $0) }
    }

    struct Pointer {
        let image: CIImage
        /// Tip position inside `image`, bottom-left space.
        let hotspot: CGPoint
    }

    /// The macOS arrow (black body, white rim, soft shadow), `height` pixels tall.
    static func pointer(height: Int) -> Pointer? {
        let unit = Double(height) / 22
        let pad = max(2, unit * 3)
        let width = Int((13.5 * unit + pad * 2).rounded(.up)), fullHeight = Int((21 * unit + pad * 2).rounded(.up))
        guard let context = rgbaContext(width, fullHeight) else { return nil }
        // Arrow outline in top-left units, tip at (0, 0).
        let outline: [(Double, Double)] = [(0, 0), (0, 16.6), (3.9, 12.9), (6.6, 19.3), (9.4, 18.1), (6.8, 11.9), (12.2, 11.9)]
        let path = CGMutablePath()
        for (index, (x, y)) in outline.enumerated() {
            let point = CGPoint(x: pad + x * unit, y: Double(fullHeight) - pad - y * unit)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        context.setLineJoin(.round)
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -unit * 0.6), blur: unit * 1.6,
                          color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.38))
        context.addPath(path)
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.setLineWidth(unit * 2.4)
        context.drawPath(using: .fillStroke)
        context.restoreGState()
        context.addPath(path)
        context.setFillColor(CGColor(srgbRed: 0.04, green: 0.04, blue: 0.05, alpha: 1))
        context.fillPath()
        guard let image = context.makeImage() else { return nil }
        return Pointer(image: CIImage(cgImage: image), hotspot: CGPoint(x: pad, y: Double(fullHeight) - pad))
    }

    /// A 256 px click ring: faint fill with a brighter rim.
    static let ripple: CIImage? = {
        let size = 256
        guard let context = rgbaContext(size, size) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: size, height: size).insetBy(dx: 10, dy: 10)
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.28))
        context.fillEllipse(in: rect)
        context.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.95))
        context.setLineWidth(12)
        context.strokeEllipse(in: rect.insetBy(dx: 6, dy: 6))
        return context.makeImage().map { CIImage(cgImage: $0) }
    }()

    /// Multiplies an image's alpha.
    static func faded(_ image: CIImage, _ opacity: Double) -> CIImage {
        guard opacity < 0.999 else { return image }
        return image.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: max(0, opacity))])
    }
}
