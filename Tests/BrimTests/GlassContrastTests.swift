import AppKit
import SwiftUI
import Testing

@testable import Brim

/// The readability promise of `GlassStyle`: on a pure white wallpaper, tinted glass keeps primary
/// text at WCAG AA and secondary text at 3:1; clear glass keeps primary text at 3:1.
@Suite struct GlassContrastTests {
  @Test func contrastMathMatchesWCAG() {
    #expect(abs(GlassContrast.ratio(1, 0) - 21) < 0.01)
    #expect(abs(GlassContrast.ratio(0.5, 0.5) - 1) < 0.0001)
    #expect(abs(GlassContrast.luminance(0.5) - 0.214) < 0.001)
  }

  @Test(arguments: GlassRole.allCases, [true, false])
  func tintedGlassKeepsTextReadable(role: GlassRole, liquid: Bool) {
    guard role != .card else { return }  // Cards draw no backdrop; they sit on glass that does.
    for clarity in stride(from: 0.0, through: 1.0, by: 0.25) {
      let prefs = GlassPreferences(tinted: true, clarity: clarity)
      let gray = prefs.materialGray(for: role, liquid: liquid)
      let veil = prefs.veil(for: role, materialGray: gray)
      let primary = GlassContrast.worstCase(veil: veil, materialGray: gray, textOpacity: GlassContrast.primaryText)
      let secondary = GlassContrast.worstCase(veil: veil, materialGray: gray, textOpacity: GlassContrast.secondaryText)
      #expect(primary >= GlassContrast.aa - 0.01, "\(role) clarity \(clarity): \(primary)")
      #expect(secondary >= GlassContrast.large - 0.01, "\(role) clarity \(clarity): \(secondary)")
    }
  }

  @Test(arguments: GlassRole.allCases)
  func clearGlassKeepsPrimaryTextLegible(role: GlassRole) {
    guard role != .card else { return }
    let prefs = GlassPreferences(tinted: false, clarity: 1)
    let gray = prefs.materialGray(for: role, liquid: true)
    let veil = prefs.veil(for: role, materialGray: gray)
    #expect(GlassContrast.worstCase(veil: veil, materialGray: gray, textOpacity: 1) >= GlassContrast.large - 0.01)
    // Clear glass really is lighter than tinted glass.
    let tinted = GlassPreferences(tinted: true, clarity: 1)
    #expect(veil < tinted.veil(for: role, materialGray: gray))
  }

  @Test func defaultShellTintIsNotLighterThanBefore() {
    // The island's tint at clarity 0.5 was 0.32 (GlassClarity); the floor may only darken it.
    let prefs = GlassPreferences()
    let veil = prefs.veil(for: .shell, materialGray: GlassMaterialGray.hudWindow)
    #expect(veil >= GlassClarity(0.5).veilOpacity(tinted: true) - 0.0001)
    #expect(veil < 0.45)
  }

  @Test func increaseContrastStrengthensTintAndRim() {
    let normal = GlassPreferences()
    let strong = GlassPreferences(increaseContrast: true)
    for role in GlassRole.allCases where role != .shell && role != .window {
      #expect(strong.stroke(for: role).top > normal.stroke(for: role).top)
      #expect(strong.stroke(for: role).width > normal.stroke(for: role).width)
    }
    #expect(strong.veil(for: .panel, materialGray: 0.2) > normal.veil(for: .panel, materialGray: 0.2))
  }

  @Test func clarityDrivesTheFrost() {
    #expect(GlassPreferences(clarity: 0).frost == 1)
    #expect(GlassPreferences(clarity: 1).frost == 0)
    #expect(GlassPreferences(clarity: 0.5).frost == 0.5)
    // Frost moves the backdrop grey from clear glass toward the frosted material.
    let clear = GlassPreferences(clarity: 1).materialGray(for: .shell, liquid: true)
    let frosted = GlassPreferences(clarity: 0).materialGray(for: .shell, liquid: true)
    #expect(clear == GlassMaterialGray.liquidClear)
    #expect(frosted == GlassMaterialGray.hudWindow)
  }
}
