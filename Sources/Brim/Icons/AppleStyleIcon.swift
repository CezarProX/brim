// AppleStyleIcon.swift
// Brim
//
// One icon look for the whole app. A feature shows the real Apple icon when macOS has one
// (`SystemIconLibrary`); features with no Apple equivalent get custom art drawn on the same
// macOS 26 grid: a continuous-corner squircle (22.37% radius) filling 824/1024 of the canvas,
// a restrained two-stop gradient, a top sheen, a 0.5pt inner light stroke and a soft drop shadow,
// with the glyph at one optical size. In the Dark icon theme the art turns into Apple's dark
// variant (near-black tile, colored glyph), so it sits naturally beside the real icons.

import SwiftUI

/// Apple's icon grid: the tile is 824 of 1024 points and its corners are 22.37% of the tile.
enum AppleIconGeometry {
  static let bodyRatio: CGFloat = 824.0 / 1024.0
  static let cornerRatio: CGFloat = 0.2237
  /// Glyph height as a share of the tile.
  static let glyphRatio: CGFloat = 0.56

  static func tile(_ body: CGFloat) -> RoundedRectangle {
    RoundedRectangle(cornerRadius: body * cornerRatio, style: .continuous)
  }
}

/// Custom icon art: an SF Symbol on a two-stop gradient.
struct AppleIconArt: Hashable {
  var symbol: String
  /// Gradient, top then bottom. In the dark theme this colors the glyph instead of the tile.
  var top: Color
  var bottom: Color
  /// Nudges the glyph's optical size for symbols that read small or large (1 = standard).
  var glyphScale: CGFloat = 1
  var decoration: Decoration = .none

  enum Decoration: Hashable { case none, checkerboard }

  init(_ symbol: String, _ top: Color, _ bottom: Color, glyphScale: CGFloat = 1, decoration: Decoration = .none) {
    self.symbol = symbol
    self.top = top
    self.bottom = bottom
    self.glyphScale = glyphScale
    self.decoration = decoration
  }

  /// Hex helper so the palettes below read like a design spec.
  static func hex(_ value: UInt32) -> Color {
    Color(
      red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255,
      blue: Double(value & 0xFF) / 255)
  }
}

/// A feature's icon: a real Apple icon when the system has one, otherwise custom art.
struct FeatureIcon: Hashable {
  var system: SystemIconSource?
  var art: AppleIconArt

  static func real(_ source: SystemIconSource, fallback art: AppleIconArt) -> FeatureIcon {
    FeatureIcon(system: source, art: art)
  }

  static func custom(_ art: AppleIconArt) -> FeatureIcon { FeatureIcon(system: nil, art: art) }

  /// Whether this icon will draw the real Apple icon on this Mac.
  @MainActor var usesSystemIcon: Bool { system.map(SystemIconLibrary.isAvailable) ?? false }
}

/// Draws a `FeatureIcon` with its visible tile `size` points wide. The canvas around it (Apple's
/// margin, where the shadow falls) overhangs the frame, so layouts size icons by what you see.
struct FeatureIconView: View {
  let icon: FeatureIcon
  let size: CGFloat
  var appearance: IconAppearance = .current
  @Environment(\.displayScale) private var displayScale

  init(_ icon: FeatureIcon, size: CGFloat, appearance: IconAppearance = .current) {
    self.icon = icon
    self.size = size
    self.appearance = appearance
  }

  var body: some View {
    let canvas = size / AppleIconGeometry.bodyRatio
    Group {
      if let source = icon.system,
         let image = SystemIconLibrary.cgImage(for: source, pixels: Int((canvas * displayScale).rounded(.up)))
      {
        Image(decorative: image, scale: displayScale).resizable().interpolation(.high)
      } else {
        AppleStyleIcon(art: icon.art, appearance: appearance)
      }
    }
    .frame(width: canvas, height: canvas)
    .frame(width: size, height: size)
    .accessibilityHidden(true)
  }
}

/// Custom art on Apple's icon grid. Fills its frame as the canvas; the tile is 824/1024 of it.
struct AppleStyleIcon: View {
  let art: AppleIconArt
  var appearance: IconAppearance = .current

  var body: some View {
    GeometryReader { proxy in
      let canvas = min(proxy.size.width, proxy.size.height)
      let body = canvas * AppleIconGeometry.bodyRatio
      tile(body)
        .frame(width: body, height: body)
        .shadow(color: .black.opacity(appearance == .dark ? 0.35 : 0.22), radius: body * 0.022, y: body * 0.012)
        .frame(width: proxy.size.width, height: proxy.size.height)
    }
  }

  private func tile(_ body: CGFloat) -> some View {
    let shape = AppleIconGeometry.tile(body)
    let dark = appearance == .dark
    return ZStack {
      shape.fill(background(dark: dark))
      if art.decoration == .checkerboard {
        AppleIconCheckerboard().clipShape(shape).opacity(dark ? 0.14 : 0.16)
      }
      glyph(body, dark: dark)
      // Sheen: light from above, gone by the middle of the tile.
      shape.fill(LinearGradient(
        colors: [.white.opacity(dark ? 0.06 : 0.22), .white.opacity(0)], startPoint: .top, endPoint: .center))
    }
    .compositingGroup()
    .overlay {
      shape.strokeBorder(
        LinearGradient(
          colors: [.white.opacity(dark ? 0.2 : 0.45), .white.opacity(dark ? 0.04 : 0.08)],
          startPoint: .top, endPoint: .bottom),
        lineWidth: max(0.5, body * 0.006))
    }
  }

  private func background(dark: Bool) -> LinearGradient {
    // Dark tiles measured off macOS 26's own dark icons: ~#1D1C1C at the top to ~#121212 below.
    let colors = dark
      ? [Color(white: 0.115), Color(white: 0.07)]
      : [art.top, art.bottom]
    return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
  }

  private func glyph(_ body: CGFloat, dark: Bool) -> some View {
    let fill: AnyShapeStyle = dark
      ? AnyShapeStyle(LinearGradient(colors: [art.top, art.bottom], startPoint: .top, endPoint: .bottom))
      : AnyShapeStyle(Color.white)
    return Image(systemName: art.symbol)
      .resizable()
      .symbolRenderingMode(.monochrome)
      .scaledToFit()
      .fontWeight(.semibold)
      .foregroundStyle(fill)
      .frame(
        width: body * AppleIconGeometry.glyphRatio * 1.15 * art.glyphScale,
        height: body * AppleIconGeometry.glyphRatio * art.glyphScale)
      .shadow(color: .black.opacity(dark ? 0 : 0.14), radius: body * 0.012, y: body * 0.008)
  }
}

/// The transparency checkerboard behind the Remove Background icon.
private struct AppleIconCheckerboard: View {
  var body: some View {
    Canvas { context, size in
      let cells = 6
      let cell = size.width / CGFloat(cells)
      for row in 0..<cells {
        for column in 0..<cells where (row + column).isMultiple(of: 2) {
          let rect = CGRect(x: CGFloat(column) * cell, y: CGFloat(row) * cell, width: cell, height: cell)
          context.fill(Path(rect), with: .color(.white.opacity(0.5)))
        }
      }
    }
  }
}
