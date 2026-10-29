// CanvasStyle.swift
// Brim
//
// The "styled background" look: a background (solid, procedural gradient,
// desktop wallpaper or custom image) around the content, with padding, a
// drop shadow, rounded corners, an optional fixed aspect ratio and the
// content's alignment inside any extra space. Pure, Codable values with no
// AppKit dependency, so screenshot presets and the video editor share them.

import CoreGraphics
import Foundation

/// An sRGB colour stored as plain numbers (Codable, Sendable).
struct RGBAColor: Codable, Hashable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double = 1

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red; self.green = green; self.blue = blue; self.alpha = alpha
    }

    /// `0xRRGGBB`.
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            alpha: alpha
        )
    }

    var cgColor: CGColor {
        CGColor(srgbRed: CGFloat(red), green: CGFloat(green), blue: CGFloat(blue), alpha: CGFloat(alpha))
    }

    func withAlpha(_ value: Double) -> RGBAColor {
        RGBAColor(red: red, green: green, blue: blue, alpha: value)
    }
}

enum CanvasBackground: Codable, Hashable, Sendable {
    case solid(RGBAColor)
    /// One of `GradientLibrary.presets`, by id.
    case gradient(id: String)
    /// The current desktop picture of the main display.
    case desktopWallpaper(blurred: Bool)
    /// A user-chosen image file.
    case image(path: String, blurred: Bool)

    enum Kind: String, CaseIterable, Sendable { case gradient, solid, wallpaper, image }

    var kind: Kind {
        switch self {
        case .solid: return .solid
        case .gradient: return .gradient
        case .desktopWallpaper: return .wallpaper
        case .image: return .image
        }
    }
}

enum CornerPreset: String, Codable, CaseIterable, Sendable {
    case square, small, medium, large

    /// Radius as a fraction of the content's geometric-mean side, which
    /// keeps corners proportionate for both tiny crops and 4K video frames.
    var radiusFactor: CGFloat {
        switch self {
        case .square: return 0
        case .small: return 0.009
        case .medium: return 0.017
        case .large: return 0.03
        }
    }
}

enum AspectPreset: String, Codable, CaseIterable, Sendable {
    case auto, wide, classic, square, portrait, twitter

    /// Width / height, or nil to hug the content.
    var ratio: CGFloat? {
        switch self {
        case .auto: return nil
        case .wide: return 16.0 / 9.0
        case .classic: return 4.0 / 3.0
        case .square: return 1
        case .portrait: return 4.0 / 5.0
        case .twitter: return 1.91
        }
    }
}

/// Where the content sits when a fixed aspect ratio leaves spare room.
enum ContentAlignment: String, Codable, CaseIterable, Sendable {
    case topLeading, top, topTrailing, leading, center, trailing, bottomLeading, bottom, bottomTrailing

    /// Unit anchor in a bottom-left-origin space: x 0 = leading, y 1 = top.
    var anchor: CGPoint {
        let x: CGFloat = [.topLeading, .leading, .bottomLeading].contains(self) ? 0
            : [.topTrailing, .trailing, .bottomTrailing].contains(self) ? 1 : 0.5
        let y: CGFloat = [.topLeading, .top, .topTrailing].contains(self) ? 1
            : [.bottomLeading, .bottom, .bottomTrailing].contains(self) ? 0 : 0.5
        return CGPoint(x: x, y: y)
    }
}

struct CanvasStyle: Codable, Hashable, Sendable {
    var isEnabled = false
    var background: CanvasBackground = .gradient(id: GradientLibrary.defaultID)
    /// Padding as a fraction of the content's mean side, 0...maxPadding.
    var padding: Double = 0.08
    /// Shadow strength, 0...1.
    var shadow: Double = 0.5
    var corners: CornerPreset = .medium
    var aspect: AspectPreset = .auto
    var alignment: ContentAlignment = .center
    /// Also round the outer canvas (transparent corners in the export).
    var roundsOuterCorners = false

    static let maxPadding = 0.3
    /// No styling: the export is the content itself.
    static let plain = CanvasStyle()
    /// What turning the toggle on starts from.
    static let styledDefault = CanvasStyle(isEnabled: true)

    init(
        isEnabled: Bool = false,
        background: CanvasBackground = .gradient(id: GradientLibrary.defaultID),
        padding: Double = 0.08,
        shadow: Double = 0.5,
        corners: CornerPreset = .medium,
        aspect: AspectPreset = .auto,
        alignment: ContentAlignment = .center,
        roundsOuterCorners: Bool = false
    ) {
        self.isEnabled = isEnabled
        self.background = background
        self.padding = padding
        self.shadow = shadow
        self.corners = corners
        self.aspect = aspect
        self.alignment = alignment
        self.roundsOuterCorners = roundsOuterCorners
    }

    /// Tolerant decoding: missing keys (older preset files) keep defaults,
    /// and out-of-range numbers are clamped.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = CanvasStyle()
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? d.isEnabled
        background = (try? c.decodeIfPresent(CanvasBackground.self, forKey: .background)) ?? d.background
        padding = min(Self.maxPadding, max(0, try c.decodeIfPresent(Double.self, forKey: .padding) ?? d.padding))
        shadow = min(1, max(0, try c.decodeIfPresent(Double.self, forKey: .shadow) ?? d.shadow))
        corners = (try? c.decodeIfPresent(CornerPreset.self, forKey: .corners)) ?? d.corners
        aspect = (try? c.decodeIfPresent(AspectPreset.self, forKey: .aspect)) ?? d.aspect
        alignment = (try? c.decodeIfPresent(ContentAlignment.self, forKey: .alignment)) ?? d.alignment
        roundsOuterCorners = try c.decodeIfPresent(Bool.self, forKey: .roundsOuterCorners) ?? d.roundsOuterCorners
    }
}
