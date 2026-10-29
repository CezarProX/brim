// GlassStyle.swift
// Brim
//
// The one place every glass surface takes its look from: which material it blurs, how dark its
// readability tint is, its sheen, hairline rim and shadow, and how it falls back under Reduce
// Transparency and Increase Contrast.

import AppKit
import SwiftUI

/// What a glass surface is for. Each role has its own tokens in `GlassTokens`.
enum GlassRole: String, CaseIterable, Sendable {
  /// The open island's shell.
  case shell
  /// Small floating pieces of the shell: the navigation capsule, back buttons.
  case capsule
  /// Floating panels: capture thumbnail, floating tray, shake actions, agent question, tour coach.
  case panel
  /// A card inside an already-glass surface (Home widgets, app pages). It layers on the glass
  /// below instead of blurring again.
  case card
  /// A whole window's background: Settings, Notes, dialogs.
  case window
}

/// Each backdrop's grey over a pure white wallpaper in Dark appearance, measured on macOS 26/27 by
/// capturing the real views (see GlassContrastTests). The readability tint is computed from these.
enum GlassMaterialGray {
  static let hudWindow = 0.696
  static let popover = 0.548
  static let underWindowBackground = 0.392
  static let liquidRegular = 0.578
  static let liquidClear = 0.847

  static func of(_ material: NSVisualEffectView.Material) -> Double {
    switch material {
    case .hudWindow: hudWindow
    case .popover, .menu: popover
    case .underWindowBackground, .sidebar, .windowBackground: underWindowBackground
    default: hudWindow
    }
  }
}

/// The fixed look of one role.
struct GlassTokens: Equatable, Sendable {
  /// AppKit material used before macOS 26, and as the frost over Liquid Glass.
  let material: NSVisualEffectView.Material
  /// Liquid Glass style on macOS 26: clear (more see-through) or regular.
  let liquidClear: Bool
  /// Dark veil at clarity 0.5 when the glass is tinted (before the readability floor).
  let tintedVeil: Double
  /// Dark veil when the user chose clear glass.
  let clearVeil: Double
  /// White highlight at the top edge, fading out by the middle.
  let sheen: Double
  /// Hairline rim, brighter at the top where light catches it.
  let strokeTop: Double
  let strokeBottom: Double
  /// Card fill (white) for `.card`, which draws no backdrop of its own.
  let cardFill: Double
  let shadow: Double
  let shadowRadius: CGFloat
  /// Grey used instead of glass under Reduce Transparency.
  let solid: Double

  static func of(_ role: GlassRole) -> GlassTokens {
    switch role {
    case .shell:
      GlassTokens(
        material: .hudWindow, liquidClear: true, tintedVeil: 0.32, clearVeil: 0.08, sheen: 0, strokeTop: 0,
        strokeBottom: 0, cardFill: 0, shadow: 0, shadowRadius: 0, solid: 0)
    case .capsule:
      GlassTokens(
        material: .hudWindow, liquidClear: false, tintedVeil: 0.62, clearVeil: 0.45, sheen: 0.07, strokeTop: 0.2,
        strokeBottom: 0.06, cardFill: 0, shadow: 0.3, shadowRadius: 6, solid: 0.04)
    case .panel:
      GlassTokens(
        material: .hudWindow, liquidClear: false, tintedVeil: 0.42, clearVeil: 0.14, sheen: 0.09, strokeTop: 0.26,
        strokeBottom: 0.07, cardFill: 0, shadow: 0.38, shadowRadius: 18, solid: 0.1)
    case .card:
      GlassTokens(
        material: .hudWindow, liquidClear: false, tintedVeil: 0, clearVeil: 0, sheen: 0.06, strokeTop: 0.16,
        strokeBottom: 0.04, cardFill: 0.075, shadow: 0, shadowRadius: 0, solid: 0.13)
    case .window:
      GlassTokens(
        material: .hudWindow, liquidClear: false, tintedVeil: 0.42, clearVeil: 0.2, sheen: 0, strokeTop: 0,
        strokeBottom: 0, cardFill: 0, shadow: 0, shadowRadius: 0, solid: 0.12)
    }
  }
}

/// WCAG 2 contrast for white text on glass. The worst case is a pure white wallpaper: the glass
/// lets `materialGray` of it through, then the tint darkens that by `veil`.
enum GlassContrast {
  /// WCAG AA for body text.
  static let aa = 4.5
  /// WCAG AA for large text and UI components.
  static let large = 3.0
  /// Text levels used on glass: `IslandInk.primary` and `.secondary`.
  static let primaryText = 1.0
  static let secondaryText = 0.62

  /// Relative luminance of an sRGB grey.
  static func luminance(_ gray: Double) -> Double {
    let c = min(1, max(0, gray))
    return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
  }

  static func ratio(_ a: Double, _ b: Double) -> Double {
    let (la, lb) = (luminance(a), luminance(b))
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
  }

  /// The grey behind the text: the backdrop through the material, darkened by the veil.
  static func background(veil: Double, materialGray: Double, backdrop: Double = 1) -> Double {
    backdrop * materialGray * (1 - min(1, max(0, veil)))
  }

  /// White text drawn at `opacity` over `background` (sRGB blending, as SwiftUI draws it).
  static func text(opacity: Double, on background: Double) -> Double {
    opacity + (1 - opacity) * background
  }

  /// Contrast of white text at `textOpacity` on glass with this veil, over the worst-case wallpaper.
  static func worstCase(veil: Double, materialGray: Double, textOpacity: Double) -> Double {
    let back = background(veil: veil, materialGray: materialGray)
    return ratio(text(opacity: textOpacity, on: back), back)
  }

  /// The lightest veil that keeps white text at `textOpacity` at `target` contrast on any wallpaper.
  static func minimumVeil(materialGray: Double, textOpacity: Double, target: Double = aa) -> Double {
    if worstCase(veil: 0, materialGray: materialGray, textOpacity: textOpacity) >= target { return 0 }
    var low = 0.0, high = 1.0
    for _ in 0..<40 {
      let mid = (low + high) / 2
      if worstCase(veil: mid, materialGray: materialGray, textOpacity: textOpacity) >= target { high = mid } else { low = mid }
    }
    return high
  }
}

/// The user's glass preferences plus the accessibility settings in force.
struct GlassPreferences: Equatable, Sendable {
  /// Tinted glass keeps every text level readable; clear glass only guarantees primary text.
  var tinted = true
  /// 0 is fully frosted, 1 fully clear. 0.5 is the default look.
  var clarity = 0.5
  var reduceTransparency = false
  var increaseContrast = false

  /// The dark veil for `role` over a backdrop with `materialGray`: the role's tint scaled by clarity
  /// as before (`GlassClarity`), never lighter than WCAG AA allows.
  func veil(for role: GlassRole, materialGray: Double) -> Double {
    let tokens = GlassTokens.of(role)
    let base = tinted ? tokens.tintedVeil : tokens.clearVeil
    let styled = min(0.9, base * 2 * (1 - min(1, max(0, clarity))))
    let floor = readabilityFloor(materialGray: materialGray)
    let boosted = increaseContrast ? styled + 0.15 : styled
    return min(0.92, max(boosted, floor))
  }

  /// The lightest veil that keeps this glass's promise on a pure white wallpaper. Tinted glass:
  /// primary text at WCAG AA (4.5:1) and secondary text at 3:1. Clear glass: primary text at 3:1.
  func readabilityFloor(materialGray: Double) -> Double {
    guard tinted else {
      return GlassContrast.minimumVeil(
        materialGray: materialGray, textOpacity: GlassContrast.primaryText, target: GlassContrast.large)
    }
    return max(
      GlassContrast.minimumVeil(materialGray: materialGray, textOpacity: GlassContrast.primaryText),
      GlassContrast.minimumVeil(
        materialGray: materialGray, textOpacity: GlassContrast.secondaryText, target: GlassContrast.large))
  }

  /// How much frosted material lies over clear Liquid Glass: none when fully clear.
  var frost: Double { 1 - min(1, max(0, clarity)) }

  /// The hairline rim: brighter and wider under Increase Contrast.
  func stroke(for role: GlassRole) -> (top: Double, bottom: Double, width: CGFloat) {
    let tokens = GlassTokens.of(role)
    guard increaseContrast else { return (tokens.strokeTop, tokens.strokeBottom, 0.75) }
    return (max(0.5, tokens.strokeTop * 2), max(0.3, tokens.strokeBottom * 3), 1)
  }

  /// The backdrop's grey over white: Liquid Glass mixed with its frost, or the AppKit material.
  func materialGray(for role: GlassRole, liquid: Bool) -> Double {
    let tokens = GlassTokens.of(role)
    guard liquid else { return GlassMaterialGray.of(tokens.material) }
    let glass = tokens.liquidClear ? GlassMaterialGray.liquidClear : GlassMaterialGray.liquidRegular
    let frosted = GlassMaterialGray.of(tokens.material)
    return glass + (frosted - glass) * frost
  }
}

/// Whether macOS 26's Liquid Glass is available to draw with.
enum GlassSupport {
  static var hasLiquidGlass: Bool {
    if #available(macOS 26.0, *) { return true }
    return false
  }
}

// MARK: - Environment

private struct GlassPreferencesOverrideKey: EnvironmentKey {
  static let defaultValue: GlassPreferences? = nil
}

private struct GlassBlendsWithinWindowKey: EnvironmentKey {
  static let defaultValue = false
}

extension EnvironmentValues {
  /// Fixed preferences for previews and render tests; nil follows Settings > Island > Theming.
  var glassPreferencesOverride: GlassPreferences? {
    get { self[GlassPreferencesOverrideKey.self] }
    set { self[GlassPreferencesOverrideKey.self] = newValue }
  }

  /// Render tests draw a wallpaper inside the window; glass then blurs within the window.
  var glassBlendsWithinWindow: Bool {
    get { self[GlassBlendsWithinWindowKey.self] }
    set { self[GlassBlendsWithinWindowKey.self] = newValue }
  }
}
