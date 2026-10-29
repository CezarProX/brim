// BackgroundResolver.swift
// Brim
//
// Turns a `CanvasBackground` description into something drawable: loads
// the desktop picture or a chosen image (downsampled, since wallpapers are
// often 6K HEICs), blurs it when asked, and caches the result. A missing or
// unreadable image falls back to the default gradient rather than failing.

import AppKit
import CoreImage
import ImageIO

@MainActor
enum BackgroundResolver {
    /// Long-side cap for decoded background images.
    static let maxImageSide = 2400
    private static var cache: [String: CGImage] = [:]
    private static let ciContext = CIContext(options: [.cacheIntermediates: false])

    static func resolve(_ background: CanvasBackground) -> ResolvedBackground {
        switch background {
        case .solid(let color):
            return .solid(color.cgColor)
        case .gradient(let id):
            return .gradient(GradientLibrary.preset(id: id) ?? fallbackGradient)
        case .desktopWallpaper(let blurred):
            guard let url = desktopPictureURL() else { return .gradient(fallbackGradient) }
            return image(at: url, blurred: blurred).map(ResolvedBackground.image) ?? .gradient(fallbackGradient)
        case .image(let path, let blurred):
            return image(at: URL(fileURLWithPath: path), blurred: blurred)
                .map(ResolvedBackground.image) ?? .gradient(fallbackGradient)
        }
    }

    static var fallbackGradient: GradientPreset {
        GradientLibrary.preset(id: GradientLibrary.defaultID) ?? GradientLibrary.presets[0]
    }

    static func desktopPictureURL() -> URL? {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return nil }
        return NSWorkspace.shared.desktopImageURL(for: screen)
    }

    /// A downsampled (and optionally blurred) image, cached by path.
    static func image(at url: URL, blurred: Bool) -> CGImage? {
        let key = "\(url.path)|\(blurred)"
        if let cached = cache[key] { return cached }
        guard let decoded = downsampledImage(at: url) else { return nil }
        let result = blurred ? (blur(decoded) ?? decoded) : decoded
        if cache.count > 8 { cache.removeAll() }
        cache[key] = result
        return result
    }

    static func downsampledImage(at url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxImageSide
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    static func blur(_ image: CGImage) -> CGImage? {
        let input = CIImage(cgImage: image)
        let sigma = Double(max(image.width, image.height)) * 0.018
        let output = input.clampedToExtent().applyingGaussianBlur(sigma: sigma).cropped(to: input.extent)
        return ciContext.createCGImage(output, from: input.extent)
    }
}
