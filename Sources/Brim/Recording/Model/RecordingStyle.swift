// RecordingStyle.swift
// Brim
//
// The "look" of an edited recording: canvas background, padding, shadow, corner rounding and how
// the redrawn pointer behaves. Saved per project and as reusable presets.

import CoreGraphics
import Foundation

struct StudioRGB: Codable, Equatable, Hashable, Sendable {
    var r: Double
    var g: Double
    var b: Double

    init(_ r: Double, _ g: Double, _ b: Double) { self.r = r; self.g = g; self.b = b }

    init(hex: UInt32) {
        self.init(Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255)
    }

    var cgColor: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: 1) }
}

/// A two- or three-stop gradient swatch from the sidebar grid.
struct StudioGradient: Equatable, Identifiable, Sendable {
    let id: Int
    let colors: [StudioRGB]
    /// Degrees; 0 runs left to right, 90 top to bottom.
    let angle: Double

    /// Fifteen swatches, three rows of five, ordered warm → cool → neutral.
    static let all: [StudioGradient] = [
        StudioGradient(id: 0, colors: [StudioRGB(hex: 0x6A5CFF), StudioRGB(hex: 0xC86DD7), StudioRGB(hex: 0xFF8A65)], angle: 35),
        StudioGradient(id: 1, colors: [StudioRGB(hex: 0xFF5F6D), StudioRGB(hex: 0xFFC371)], angle: 45),
        StudioGradient(id: 2, colors: [StudioRGB(hex: 0xF7797D), StudioRGB(hex: 0xFBD786), StudioRGB(hex: 0xC6FFDD)], angle: 60),
        StudioGradient(id: 3, colors: [StudioRGB(hex: 0xFC466B), StudioRGB(hex: 0x3F5EFB)], angle: 30),
        StudioGradient(id: 4, colors: [StudioRGB(hex: 0xFF9A8B), StudioRGB(hex: 0xFF6A88), StudioRGB(hex: 0xFF99AC)], angle: 50),
        StudioGradient(id: 5, colors: [StudioRGB(hex: 0x00C6FB), StudioRGB(hex: 0x005BEA)], angle: 40),
        StudioGradient(id: 6, colors: [StudioRGB(hex: 0x43E97B), StudioRGB(hex: 0x38F9D7)], angle: 45),
        StudioGradient(id: 7, colors: [StudioRGB(hex: 0x4FACFE), StudioRGB(hex: 0x00F2FE)], angle: 60),
        StudioGradient(id: 8, colors: [StudioRGB(hex: 0x667EEA), StudioRGB(hex: 0x764BA2)], angle: 45),
        StudioGradient(id: 9, colors: [StudioRGB(hex: 0x0BA360), StudioRGB(hex: 0x3CBA92), StudioRGB(hex: 0x30DD8A)], angle: 30),
        StudioGradient(id: 10, colors: [StudioRGB(hex: 0x1E3C72), StudioRGB(hex: 0x2A5298)], angle: 40),
        StudioGradient(id: 11, colors: [StudioRGB(hex: 0x232526), StudioRGB(hex: 0x414345)], angle: 60),
        StudioGradient(id: 12, colors: [StudioRGB(hex: 0x0F2027), StudioRGB(hex: 0x203A43), StudioRGB(hex: 0x2C5364)], angle: 35),
        StudioGradient(id: 13, colors: [StudioRGB(hex: 0xE0C3FC), StudioRGB(hex: 0x8EC5FC)], angle: 45),
        StudioGradient(id: 14, colors: [StudioRGB(hex: 0xFDFBFB), StudioRGB(hex: 0xEBEDEE)], angle: 90),
    ]

    static func preset(_ id: Int) -> StudioGradient { all.first { $0.id == id } ?? all[0] }
}

enum StudioBackground: Codable, Equatable, Hashable, Sendable {
    case gradient(Int)
    case solid(StudioRGB)

    static let solidChoices: [StudioRGB] = [
        StudioRGB(hex: 0x111114), StudioRGB(hex: 0x2C2C30), StudioRGB(hex: 0xF2F2F5), StudioRGB(hex: 0x3A59F5), StudioRGB(hex: 0xFF5A4E),
        StudioRGB(hex: 0xFFB238), StudioRGB(hex: 0x30C26B), StudioRGB(hex: 0x1FB4D8), StudioRGB(hex: 0x8E5CF7), StudioRGB(hex: 0xF25FA8),
    ]
}

enum StudioCornerStyle: String, Codable, CaseIterable, Sendable {
    case square, small, medium, large

    var title: String {
        switch self {
        case .square: "Square"
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        }
    }

    /// Radius as a share of the frame's shorter side.
    var factor: Double {
        switch self {
        case .square: 0
        case .small: 0.012
        case .medium: 0.026
        case .large: 0.05
        }
    }
}

struct StudioCursorStyle: Codable, Equatable, Sendable {
    var isVisible = true
    /// Multiplier on the real pointer size.
    var size: Double = 1.5
    /// 0 = raw path, 1 = very smooth.
    var smoothing: Double = 0.55
    var hidesWhenIdle = true
    var clickRipple = true

    static let sizeRange: ClosedRange<Double> = 0.6...4
}

struct RecordingStyle: Codable, Equatable, Sendable {
    var background: StudioBackground = .gradient(0)
    /// Share of the canvas' shorter side left around the recording.
    var padding: Double = 0.06
    /// 0...1 strength.
    var shadow: Double = 0.45
    var corners: StudioCornerStyle = .medium
    var cursor = StudioCursorStyle()

    static let paddingRange: ClosedRange<Double> = 0...0.3
    static let standard = RecordingStyle()
}

struct StudioStylePreset: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var name: String
    var style: RecordingStyle
}

/// A region blurred or pixelated for part of the recording ("hidden area").
struct HiddenArea: Codable, Equatable, Identifiable, Sendable {
    enum Kind: String, Codable, CaseIterable, Sendable { case blur, pixelate }

    var id = UUID()
    /// Normalised source rect, top-left origin.
    var rect: CGRect
    /// Source seconds.
    var start: Double
    var end: Double
    var kind: Kind = .blur

    func isActive(at t: Double) -> Bool { t >= start && t < end }
}

/// Everything the user changed about one recording. Saved as `edit.json` in the project.
struct StudioEdit: Codable, Equatable, Sendable {
    var timeline: EditTimeline
    var zooms: [ZoomSegment] = []
    var hiddenAreas: [HiddenArea] = []
    var style = RecordingStyle()
    /// Normalised crop of the source, top-left origin.
    var crop = CGRect(x: 0, y: 0, width: 1, height: 1)

    init(sourceDuration: Double) {
        timeline = EditTimeline(sourceDuration: sourceDuration)
    }

    /// A fresh edit with automatic zooms from the recorded clicks.
    static func initial(duration: Double, track: CursorTrack, style: RecordingStyle = .standard) -> StudioEdit {
        var edit = StudioEdit(sourceDuration: duration)
        edit.style = style
        edit.zooms = AutoZoomGenerator.segments(clicks: track.clicks, duration: duration)
        return edit
    }

    static func clampedCrop(_ rect: CGRect) -> CGRect {
        let minimum = 0.05
        var r = rect.standardized
        r.size.width = min(max(r.width, minimum), 1)
        r.size.height = min(max(r.height, minimum), 1)
        r.origin.x = min(max(r.minX, 0), 1 - r.width)
        r.origin.y = min(max(r.minY, 0), 1 - r.height)
        return r
    }
}
