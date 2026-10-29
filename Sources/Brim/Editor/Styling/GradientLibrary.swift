// GradientLibrary.swift
// Brim
//
// Twenty procedural backgrounds. Each is a linear base gradient plus a few
// soft colour "blobs" (radial falloffs) layered on top, which reads like a
// mesh gradient without shipping any artwork. Everything is generated at
// draw time, at any resolution.

import CoreGraphics

struct GradientBlob: Hashable, Sendable {
    var color: RGBAColor
    /// Centre as a unit point in a bottom-left-origin canvas.
    var center: CGPoint
    /// Radius as a fraction of the canvas's longer side.
    var radius: CGFloat
}

struct GradientPreset: Identifiable, Hashable, Sendable {
    let id: String
    /// English display name (localized at the UI layer).
    let name: String
    let stops: [RGBAColor]
    /// Direction of the base gradient in degrees (0 = left to right, 90 = bottom to top).
    let angle: CGFloat
    let blobs: [GradientBlob]
}

enum GradientLibrary {
    static let defaultID = "aurora"

    static func preset(id: String) -> GradientPreset? { presets.first { $0.id == id } }

    private static func blob(_ hex: UInt32, _ x: CGFloat, _ y: CGFloat, _ r: CGFloat, alpha: Double = 0.85) -> GradientBlob {
        GradientBlob(color: RGBAColor(hex: hex, alpha: alpha), center: CGPoint(x: x, y: y), radius: r)
    }

    private static func make(_ id: String, _ name: String, _ hexes: [UInt32], _ angle: CGFloat,
                             _ blobs: [GradientBlob] = []) -> GradientPreset {
        GradientPreset(id: id, name: name, stops: hexes.map { RGBAColor(hex: $0) }, angle: angle, blobs: blobs)
    }

    static let presets: [GradientPreset] = [
        make("aurora", "Aurora", [0x2B1B6B, 0x3A49C9, 0x2FB4C9], 35,
             [blob(0x8C4BFF, 0.15, 0.85, 0.55), blob(0x34E0B0, 0.85, 0.2, 0.5, alpha: 0.7)]),
        make("sunset", "Sunset", [0xFF5E62, 0xFF9966, 0xFFC371], 70,
             [blob(0xC2185B, 0.1, 0.1, 0.6, alpha: 0.7)]),
        make("ocean", "Ocean", [0x0F2027, 0x1C5A85, 0x2C9FD6], 60,
             [blob(0x48D1F0, 0.8, 0.85, 0.5, alpha: 0.6)]),
        make("candy", "Candy", [0xFF8FD8, 0xB98CFF, 0x7FB2FF], 20,
             [blob(0xFFE29A, 0.9, 0.9, 0.4, alpha: 0.55)]),
        make("forest", "Forest", [0x0B3D2E, 0x1E7A4F, 0x7BC67B], 75,
             [blob(0xC8E66B, 0.85, 0.85, 0.45, alpha: 0.5)]),
        make("ember", "Ember", [0x3A0A0A, 0xB3261E, 0xFF7A1A], 55,
             [blob(0xFFC34D, 0.9, 0.15, 0.45, alpha: 0.6)]),
        make("lavender", "Lavender", [0xC9B6FF, 0xE6D9FF, 0xFAD4F0], 30,
             [blob(0x9C7BFF, 0.1, 0.1, 0.55, alpha: 0.55)]),
        make("mint", "Mint", [0xB8F5DA, 0x7DE3C3, 0x46C2B4], 110,
             [blob(0xE8FFF4, 0.2, 0.9, 0.5, alpha: 0.6)]),
        make("midnight", "Midnight", [0x07070F, 0x161A3A, 0x2A2F6B], 80,
             [blob(0x5A4FCF, 0.8, 0.9, 0.5, alpha: 0.55), blob(0xB04BD9, 0.1, 0.1, 0.45, alpha: 0.35)]),
        make("peach", "Peach", [0xFFD3B6, 0xFFAAA5, 0xFF8B94], 45,
             [blob(0xFFF1C9, 0.15, 0.85, 0.5, alpha: 0.6)]),
        make("sky", "Sky", [0x89C2FF, 0xB5DCFF, 0xEAF4FF], 90,
             [blob(0x5B9BFF, 0.1, 0.05, 0.6, alpha: 0.5)]),
        make("grape", "Grape", [0x41295A, 0x6B2F9C, 0xC33764], 135,
             [blob(0xFF7EB3, 0.9, 0.1, 0.45, alpha: 0.5)]),
        make("coral", "Coral", [0xFF6F61, 0xFF9A8B, 0xFFC1A6], 160,
             [blob(0xFF3F7F, 0.85, 0.85, 0.45, alpha: 0.45)]),
        make("lime", "Lime", [0xD4FC79, 0x96E6A1, 0x4FC3A1], 25,
             [blob(0xFFF59D, 0.1, 0.9, 0.45, alpha: 0.6)]),
        make("mango", "Mango", [0xFFB000, 0xFF8A00, 0xFF5C39], 100,
             [blob(0xFFE066, 0.2, 0.85, 0.5, alpha: 0.65)]),
        make("dusk", "Dusk", [0x2C3E73, 0x7B4F9E, 0xF28CA8], 95,
             [blob(0xFFB88C, 0.85, 0.15, 0.45, alpha: 0.55)]),
        make("rose", "Rose", [0xF4C4D0, 0xE8869E, 0xC0466E], 120,
             [blob(0xFFE3EA, 0.15, 0.85, 0.5, alpha: 0.6)]),
        make("glacier", "Glacier", [0xE0F7FA, 0x9ED8F0, 0x5FA8D3], 150,
             [blob(0xFFFFFF, 0.8, 0.85, 0.45, alpha: 0.6)]),
        make("neon", "Neon", [0x12002B, 0x3D00B8, 0x00D4FF], 40,
             [blob(0xFF00C8, 0.85, 0.85, 0.45, alpha: 0.55), blob(0x00FFA3, 0.1, 0.1, 0.4, alpha: 0.35)]),
        make("slate", "Slate", [0x1F2328, 0x3A4049, 0x5B6573], 70,
             [blob(0x8C96A3, 0.85, 0.9, 0.5, alpha: 0.35)])
    ]
}
