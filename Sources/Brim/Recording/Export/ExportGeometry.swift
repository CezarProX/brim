// ExportGeometry.swift
// Brim
//
// Pure layout maths shared by the preview and the export compositor: how big the canvas is, where
// the recording sits on it, how round and how shadowed it is, and how the zoom camera maps source
// points onto the canvas. All rects here use a top-left origin; the renderer flips for Core Image.

import CoreGraphics
import Foundation

enum ExportFormat: String, Codable, CaseIterable, Sendable {
    case mp4, gif

    var fileExtension: String { rawValue }
    var title: String { self == .mp4 ? "MP4" : "GIF" }
}

enum ExportCodec: String, Codable, CaseIterable, Sendable {
    case h264, hevc

    var title: String { self == .h264 ? "H.264" : "HEVC" }
}

enum ExportResolution: String, Codable, CaseIterable, Sendable {
    case source, p1080, p720, p480

    var title: String {
        switch self {
        case .source: "Original"
        case .p1080: "1080p"
        case .p720: "720p"
        case .p480: "480p"
        }
    }

    /// Target shorter side; nil keeps the recording's size.
    var shortSide: Double? {
        switch self {
        case .source: nil
        case .p1080: 1080
        case .p720: 720
        case .p480: 480
        }
    }
}

enum ExportAspect: String, Codable, CaseIterable, Sendable {
    case auto, wide, square, vertical

    var title: String {
        switch self {
        case .auto: "Match the recording"
        case .wide: "16:9"
        case .square: "1:1"
        case .vertical: "9:16"
        }
    }

    /// Width over height; nil follows the recording.
    var ratio: Double? {
        switch self {
        case .auto: nil
        case .wide: 16.0 / 9.0
        case .square: 1
        case .vertical: 9.0 / 16.0
        }
    }
}

struct ExportSettings: Codable, Equatable, Sendable {
    var format: ExportFormat = .mp4
    var codec: ExportCodec = .h264
    var resolution: ExportResolution = .p1080
    var aspect: ExportAspect = .auto
    var fps: Int = 60
    var gifFPS: Int = 15

    static let fpsChoices = [24, 30, 60]
    static let gifFPSChoices = [10, 15, 24]

    var effectiveFPS: Int { format == .gif ? gifFPS : fps }
    /// GIFs are capped smaller; they balloon quickly.
    var effectiveResolution: ExportResolution {
        guard format == .gif else { return resolution }
        return resolution == .source || resolution == .p1080 ? .p720 : resolution
    }
}

struct FrameLayout: Equatable, Sendable {
    var canvas: CGSize
    /// Where the (cropped) recording is drawn, top-left origin.
    var videoRect: CGRect
    var cornerRadius: Double
    var shadowRadius: Double
    var shadowOpacity: Double
    var shadowOffset: Double
}

enum ExportGeometry {
    /// Even dimensions (H.264/HEVC need them), fitted to the resolution's shorter side, never upscaled
    /// past the recording itself for `.source`.
    static func canvasSize(content: CGSize, resolution: ExportResolution, aspect: ExportAspect) -> CGSize {
        guard content.width > 0, content.height > 0 else { return CGSize(width: 2, height: 2) }
        let ratio = aspect.ratio ?? Double(content.width / content.height)
        var width: Double, height: Double
        if let short = resolution.shortSide {
            if ratio >= 1 { height = short; width = short * ratio } else { width = short; height = short / ratio }
        } else if aspect.ratio == nil {
            width = Double(content.width); height = Double(content.height)
        } else {
            // Original resolution with a forced aspect: the canvas encloses the recording.
            let contentRatio = Double(content.width / content.height)
            if ratio >= contentRatio { height = Double(content.height); width = height * ratio }
            else { width = Double(content.width); height = width / ratio }
        }
        return CGSize(width: even(width), height: even(height))
    }

    static func even(_ value: Double) -> Double { max(2, (value / 2).rounded() * 2) }

    /// Aspect-fits `content` inside the canvas minus padding.
    static func layout(canvas: CGSize, content: CGSize, style: RecordingStyle) -> FrameLayout {
        let shortSide = Double(min(canvas.width, canvas.height))
        let inset = min(max(style.padding, RecordingStyle.paddingRange.lowerBound), RecordingStyle.paddingRange.upperBound) * shortSide
        let available = CGRect(origin: .zero, size: canvas).insetBy(dx: inset, dy: inset)
        let videoRect = aspectFit(content, in: available)
        let videoShort = Double(min(videoRect.width, videoRect.height))
        let strength = min(max(style.shadow, 0), 1)
        return FrameLayout(
            canvas: canvas, videoRect: videoRect,
            cornerRadius: style.corners.factor * videoShort,
            shadowRadius: strength * 0.045 * shortSide,
            shadowOpacity: strength * 0.75,
            shadowOffset: strength * 0.012 * shortSide)
    }

    static func aspectFit(_ size: CGSize, in rect: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0, rect.width > 0, rect.height > 0 else { return rect }
        let scale = min(rect.width / size.width, rect.height / size.height)
        let fitted = CGSize(width: size.width * scale, height: size.height * scale)
        return CGRect(x: rect.midX - fitted.width / 2, y: rect.midY - fitted.height / 2, width: fitted.width, height: fitted.height)
    }

    /// Canvas point (top-left) for a normalised point of the cropped content, through the camera.
    static func canvasPoint(_ p: CGPoint, layout: FrameLayout, camera: CameraState) -> CGPoint {
        let visible = camera.visibleRect
        let u = (Double(p.x) - Double(visible.minX)) / Double(visible.width)
        let v = (Double(p.y) - Double(visible.minY)) / Double(visible.height)
        return CGPoint(x: layout.videoRect.minX + u * layout.videoRect.width, y: layout.videoRect.minY + v * layout.videoRect.height)
    }

    /// Converts a normalised source point (full recording) into the cropped content's normalised space.
    static func cropped(_ p: CGPoint, crop: CGRect) -> CGPoint {
        CGPoint(x: (p.x - crop.minX) / max(crop.width, 0.0001), y: (p.y - crop.minY) / max(crop.height, 0.0001))
    }

    /// Canvas pixels per captured point at a camera scale (pointer and ripple sizes).
    static func pointScale(layout: FrameLayout, contentPoints: CGSize, camera: CameraState) -> Double {
        guard contentPoints.height > 0 else { return 1 }
        return Double(layout.videoRect.height) / Double(contentPoints.height) * camera.scale
    }
}
