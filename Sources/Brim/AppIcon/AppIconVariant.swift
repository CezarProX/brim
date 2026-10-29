// AppIconVariant.swift
// Brim
//
// The app icon choices (the Brim icon plus four colourways of it) and the setting that remembers the
// pick. The default is the Brim logo (Resources/AppIcon/BrimLogo.png, baked into the bundle's Brim.icns
// by build_app.sh); the colourways are the Brim mark drawn in code (BrimIconArt) and are applied with
// `NSApp.applicationIconImage`.

import AppKit

enum AppIconVariant: String, CaseIterable, Identifiable, Sendable {
  case standard
  case midnight
  case sunset
  case aurora
  case paper

  var id: String { rawValue }

  var title: String {
    switch self {
    case .standard: String(localized: "Default")
    case .midnight: String(localized: "Midnight")
    case .sunset: String(localized: "Sunset")
    case .aurora: String(localized: "Aurora")
    case .paper: String(localized: "Paper")
    }
  }

  /// The colours each look paints the Brim mark with.
  var palette: BrimIconPalette {
    switch self {
    case .standard: .brim
    case .midnight:
      BrimIconPalette(top: 0x0B0B10, mid: 0x18181F, bottom: 0x2A2A35, glow: 0x8C9BFF,
                      surface: 0xFFFFFF, shallow: 0xB4BEFF, deep: 0x5B66D6, deepest: 0x2E3380,
                      island: 0x000000, islandHighlight: 0x2C2C33)
    case .sunset:
      BrimIconPalette(top: 0x3A0F4F, mid: 0xA42C6B, bottom: 0xFF7A45, glow: 0xFFC46B,
                      surface: 0xFFF6E0, shallow: 0xFFCB70, deep: 0xFF8A3D, deepest: 0xE0306E)
    case .aurora:
      BrimIconPalette(top: 0x062A3A, mid: 0x0F6E7A, bottom: 0x1FB89A, glow: 0x7CFFD9,
                      surface: 0xF0FFF9, shallow: 0x7CFFD9, deep: 0x27D3A8, deepest: 0x138A8F)
    case .paper:
      BrimIconPalette(top: 0xFFFFFF, mid: 0xF1F3F7, bottom: 0xDCE1EA, glow: 0x9FC3FF,
                      surface: 0xEAF5FF, shallow: 0x8CC2FF, deep: 0x4E8DFF, deepest: 0x2C5FE0,
                      island: 0x111114, islandHighlight: 0x3A3A44)
    }
  }
}

extension AppSettings {
  private static let appIconKey = "appIconVariant"

  var appIconVariant: AppIconVariant {
    get { AppIconVariant(rawValue: defaults.string(forKey: Self.appIconKey) ?? "") ?? .standard }
    set { defaults.set(newValue.rawValue, forKey: Self.appIconKey) }
  }
}

/// Applies the saved icon at launch and when the picker changes it.
@MainActor
enum AppIconController {
  /// Sets the running app's icon to `variant` and remembers it.
  static func select(_ variant: AppIconVariant, settings: AppSettings = .shared) {
    settings.appIconVariant = variant
    apply(variant)
  }

  /// Draws and applies the saved variant. Call once from `applicationDidFinishLaunching`.
  static func applySaved(settings: AppSettings = .shared) {
    apply(settings.appIconVariant)
  }

  private static func apply(_ variant: AppIconVariant) {
    // The default is the bundle's own Brim.icns (the logo); nil hands the Dock back to it.
    // Without a bundled icon (swift run, tests) it is drawn like the others.
    let bundled = Bundle.main.object(forInfoDictionaryKey: "CFBundleIconFile") != nil
    NSApp?.applicationIconImage = variant == .standard && bundled ? nil : AppIconRenderer.image(for: variant, size: 512)
  }
}
