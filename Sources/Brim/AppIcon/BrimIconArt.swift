// BrimIconArt.swift
// Brim
//
// The Brim app icon and menu-bar glyph, drawn with plain CoreGraphics so the very same art is used
// at runtime (alternate icons, the Settings picker) and by build_app.sh, which compiles this file on
// its own to render the bundle's .icns. Keep it free of app types.
//
// Geometry follows Apple's macOS icon grid: a 1024 canvas, an 824 squircle with a soft drop shadow.
// The mark: the island (a glossy black pill at the top) over a tile filled to the brim, the liquid
// rising toward it while a drop falls in. 16 and 32 px get their own pixel-snapped cut so the
// small sizes stay crisp instead of being a blurred copy of the big one.

import CoreGraphics
import Foundation

/// The colours of one Brim icon look, as sRGB hex.
struct BrimIconPalette: Equatable, Sendable {
  var top: UInt32
  var mid: UInt32
  var bottom: UInt32
  /// Light that spills from the liquid onto the tile.
  var glow: UInt32
  /// Liquid colours from the bright surface down to the deepest part.
  var surface: UInt32
  var shallow: UInt32
  var deep: UInt32
  var deepest: UInt32
  /// The island pill.
  var island: UInt32 = 0x050508
  var islandHighlight: UInt32 = 0x34343F

  static let brim = BrimIconPalette(
    top: 0x130E4E, mid: 0x2A23A8, bottom: 0x3D5BFF, glow: 0x4FD8FF,
    surface: 0xE9FDFF, shallow: 0x6DE7FF, deep: 0x2F7BFF, deepest: 0x2346D8)
}

enum BrimIconArt {
  /// How much of the art a size can carry.
  enum Detail: Equatable { case tiny, small, full }

  static func detail(forPixels pixels: CGFloat) -> Detail {
    pixels < 24 ? .tiny : pixels < 64 ? .small : .full
  }

  /// Draws the icon into a `size`-wide square of `ctx` (usual bottom-left origin). The context's
  /// own scale (2 on Retina) counts toward the pixel size that picks the small cuts.
  static func draw(in ctx: CGContext, size: CGFloat, palette: BrimIconPalette = .brim) {
    let pixels = size * max(1, abs(ctx.ctm.a))
    let layout = Layout(detail: detail(forPixels: pixels))
    ctx.saveGState()
    ctx.translateBy(x: 0, y: size)
    ctx.scaleBy(x: size / 1024, y: -size / 1024)
    let shape = squircle(layout.body)
    drawShadow(ctx, shape: shape, pixels: pixels, palette: palette)
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    // Small sizes start the gradient lighter so the black island keeps its contrast.
    let top = layout.detail == .full ? palette.top : palette.mid
    linear(ctx, [rgb(top), rgb(palette.mid), rgb(palette.bottom)], locations: [0, 0.5, 1],
           from: CGPoint(x: 330, y: 100), to: CGPoint(x: 694, y: 924))
    drawLiquid(ctx, layout: layout, palette: palette)
    drawIsland(ctx, layout: layout, palette: palette)
    if layout.detail == .full {
      linear(ctx, [rgb(0xFFFFFF, 0.10), rgb(0xFFFFFF, 0)], from: CGPoint(x: 512, y: 100), to: CGPoint(x: 512, y: 400))
    }
    ctx.restoreGState()
    if layout.detail == .full { drawRim(ctx, shape: shape) }
    ctx.restoreGState()
  }

  // MARK: Layout

  /// Every shape's place on the 1024 grid; the two small cuts are snapped to their pixel grids.
  struct Layout {
    let detail: Detail
    let body: CGRect
    let island: CGRect
    /// The liquid's resting level at the tile edges and how far its crest rises above that.
    let level: CGFloat
    let crest: CGFloat
    /// The falling drop's round part; nil when the size is too small to show it.
    let drop: (centre: CGPoint, radius: CGFloat)?

    init(detail: Detail) {
      self.detail = detail
      switch detail {
      case .full:
        body = CGRect(x: 100, y: 100, width: 824, height: 824)
        island = CGRect(x: 292, y: 178, width: 440, height: 138)
        level = 668; crest = 156
        drop = (CGPoint(x: 512, y: 436), 50)
      case .small:  // 32 px grid: one pixel is 32 units.
        let u: CGFloat = 32
        body = CGRect(x: 3 * u, y: 3 * u, width: 26 * u, height: 26 * u)
        island = CGRect(x: 9 * u, y: 6 * u, width: 14 * u, height: 4 * u)
        level = 22 * u; crest = 5 * u
        drop = (CGPoint(x: 16 * u, y: 13.5 * u), 1.6 * u)
      case .tiny:  // 16 px grid: one pixel is 64 units.
        let u: CGFloat = 64
        body = CGRect(x: 1 * u, y: 1 * u, width: 14 * u, height: 14 * u)
        island = CGRect(x: 4 * u, y: 3 * u, width: 8 * u, height: 2 * u)
        level = 11.5 * u; crest = 3.5 * u
        drop = nil
      }
    }
  }

  // MARK: Body

  /// Apple's continuous-corner squircle, approximated by a superellipse (n = 5).
  static func squircle(_ r: CGRect) -> CGPath {
    let path = CGMutablePath()
    let a = r.width / 2, b = r.height / 2, cx = r.midX, cy = r.midY
    let n: CGFloat = 5
    let steps = 360
    for i in 0...steps {
      let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
      let c = cos(t), s = sin(t)
      let point = CGPoint(x: cx + a * copysign(pow(abs(c), 2 / n), c), y: cy + b * copysign(pow(abs(s), 2 / n), s))
      if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
    }
    path.closeSubpath()
    return path
  }

  private static func drawShadow(_ ctx: CGContext, shape: CGPath, pixels: CGFloat, palette: BrimIconPalette) {
    let k = pixels / 1024
    ctx.saveGState()
    // Shadow offsets ignore the CTM, so they are in device pixels (negative = down).
    ctx.setShadow(offset: CGSize(width: 0, height: -10 * k), blur: 20 * k, color: rgb(0x000000, 0.3))
    ctx.addPath(shape)
    ctx.setFillColor(rgb(palette.top))
    ctx.fillPath()
    ctx.restoreGState()
  }

  private static func drawRim(_ ctx: CGContext, shape: CGPath) {
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    ctx.addPath(shape)
    ctx.setLineWidth(4)
    ctx.setStrokeColor(rgb(0xFFFFFF, 0.18))
    ctx.strokePath()
    ctx.restoreGState()
  }

  // MARK: Island

  private static func drawIsland(_ ctx: CGContext, layout: Layout, palette: BrimIconPalette) {
    let rect = layout.island
    let pill = CGPath(roundedRect: rect, cornerWidth: rect.height / 2, cornerHeight: rect.height / 2, transform: nil)
    ctx.saveGState()
    if layout.detail == .full {
      // A faint glow so the black pill separates from the dark top of the tile.
      ctx.setShadow(offset: .zero, blur: 40 * ctx.ctm.a, color: rgb(palette.glow, 0.35))
    }
    ctx.addPath(pill)
    ctx.setFillColor(rgb(palette.island))
    ctx.fillPath()
    ctx.restoreGState()
    guard layout.detail == .full else { return }
    ctx.saveGState()
    ctx.addPath(pill)
    ctx.clip()
    linear(ctx, [rgb(palette.islandHighlight), rgb(palette.island)], locations: [0, 0.5],
           from: CGPoint(x: rect.midX, y: rect.minY), to: CGPoint(x: rect.midX, y: rect.maxY))
    // Glassy reflection across the top.
    let gloss = CGRect(x: rect.minX + 44, y: rect.minY + 9, width: rect.width - 88, height: rect.height * 0.30)
    ctx.addPath(CGPath(roundedRect: gloss, cornerWidth: gloss.height / 2, cornerHeight: gloss.height / 2, transform: nil))
    ctx.clip()
    linear(ctx, [rgb(0xFFFFFF, 0.13), rgb(0xFFFFFF, 0.0)],
           from: CGPoint(x: rect.midX, y: gloss.minY), to: CGPoint(x: rect.midX, y: gloss.maxY))
    ctx.restoreGState()
    // The camera lens at the right end of the pill.
    let lens = CGRect(x: rect.maxX - 96, y: rect.midY - 22, width: 44, height: 44)
    ctx.saveGState()
    ctx.addEllipse(in: lens)
    ctx.clip()
    radial(ctx, [rgb(0x3D5DB0), rgb(0x0E1120)], centre: CGPoint(x: lens.midX - 6, y: lens.midY - 6), radius: 26)
    ctx.restoreGState()
    ctx.setFillColor(rgb(0xC8DAFF, 0.75))
    ctx.fillEllipse(in: CGRect(x: lens.midX - 11, y: lens.midY - 12, width: 9, height: 9))
  }

  // MARK: Liquid

  private static func drawLiquid(_ ctx: CGContext, layout: Layout, palette: BrimIconPalette) {
    let full = layout.detail == .full
    let level = layout.level, crest = layout.crest
    let top = level - crest
    // The liquid lights the tile above it.
    if layout.detail != .tiny {
      radial(ctx, [rgb(palette.glow, full ? 0.55 : 0.35), rgb(palette.glow, 0)],
             centre: CGPoint(x: 512, y: top + 60), radius: full ? 380 : 300)
    }
    if full {
      // A second wave behind, out of phase, for depth.
      ctx.saveGState()
      ctx.addPath(wave(level: level - 40, crest: crest * 0.55, crestX: 640))
      ctx.clip()
      linear(ctx, [rgb(palette.shallow, 0.38), rgb(palette.deep, 0)],
             from: CGPoint(x: 512, y: top), to: CGPoint(x: 512, y: level + 80))
      ctx.restoreGState()
    }
    ctx.saveGState()
    ctx.addPath(wave(level: level, crest: crest, crestX: 512))
    ctx.clip()
    linear(ctx, [rgb(palette.surface), rgb(palette.shallow), rgb(palette.deep), rgb(palette.deepest)],
           locations: full ? [0, 0.16, 0.55, 1] : [0, 0.25, 0.6, 1],
           from: CGPoint(x: 512, y: top), to: CGPoint(x: 512, y: 924))
    ctx.restoreGState()
    if full {
      // Specular line along the surface, brightest at the crest.
      ctx.saveGState()
      ctx.addPath(surface(level: level, crest: crest, crestX: 512))
      ctx.setLineWidth(9)
      ctx.setLineCap(.round)
      ctx.replacePathWithStrokedPath()
      ctx.clip()
      linear(ctx, [rgb(0xFFFFFF, 0), rgb(0xFFFFFF, 0.95), rgb(0xFFFFFF, 0)], locations: [0.1, 0.5, 0.9],
             from: CGPoint(x: 100, y: 0), to: CGPoint(x: 924, y: 0))
      ctx.restoreGState()
    }
    if let drop = layout.drop { drawDrop(ctx, centre: drop.centre, radius: drop.radius, palette: palette, full: full) }
  }

  private static func drawDrop(_ ctx: CGContext, centre c: CGPoint, radius r: CGFloat, palette: BrimIconPalette, full: Bool) {
    let shape: CGPath = full ? teardrop(centre: c, radius: r, height: 2.3)
      : CGPath(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r), transform: nil)
    ctx.saveGState()
    if full { ctx.setShadow(offset: .zero, blur: 30 * ctx.ctm.a, color: rgb(palette.glow, 0.8)) }
    ctx.addPath(shape)
    ctx.setFillColor(rgb(palette.shallow))
    ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    linear(ctx, [rgb(palette.surface), rgb(palette.shallow), rgb(palette.deep)], locations: [0, 0.55, 1],
           from: CGPoint(x: c.x, y: c.y - r * 2.3), to: CGPoint(x: c.x, y: c.y + r))
    if full {
      let h = CGPoint(x: c.x - r * 0.36, y: c.y - r * 0.12)
      radial(ctx, [rgb(0xFFFFFF, 0.95), rgb(0xFFFFFF, 0)], centre: h, radius: r * 0.36)
    }
    ctx.restoreGState()
  }

  /// The liquid's surface line, from the left edge over the crest to the right edge.
  private static func surface(level: CGFloat, crest: CGFloat, crestX: CGFloat) -> CGMutablePath {
    let top = level - crest
    let path = CGMutablePath()
    path.move(to: CGPoint(x: 40, y: level + crest * 0.08))
    path.addCurve(to: CGPoint(x: crestX, y: top),
                  control1: CGPoint(x: 40 + (crestX - 40) * 0.42, y: level + crest * 0.1),
                  control2: CGPoint(x: crestX - (crestX - 40) * 0.36, y: top))
    path.addCurve(to: CGPoint(x: 984, y: level + crest * 0.08),
                  control1: CGPoint(x: crestX + (984 - crestX) * 0.36, y: top),
                  control2: CGPoint(x: 984 - (984 - crestX) * 0.42, y: level + crest * 0.1))
    return path
  }

  private static func wave(level: CGFloat, crest: CGFloat, crestX: CGFloat) -> CGPath {
    let path = surface(level: level, crest: crest, crestX: crestX)
    path.addLine(to: CGPoint(x: 984, y: 1000))
    path.addLine(to: CGPoint(x: 40, y: 1000))
    path.closeSubpath()
    return path
  }

  /// A drop with its point upward; `height` is its overall height in radii.
  private static func teardrop(centre c: CGPoint, radius r: CGFloat, height: CGFloat) -> CGPath {
    let tip = CGPoint(x: c.x, y: c.y - r * height)
    let path = CGMutablePath()
    path.move(to: tip)
    path.addCurve(to: CGPoint(x: c.x + r, y: c.y),
                  control1: CGPoint(x: c.x + r * 0.2, y: tip.y + r * 0.55), control2: CGPoint(x: c.x + r, y: c.y - r * 0.7))
    path.addArc(center: c, radius: r, startAngle: 0, endAngle: .pi, clockwise: false)
    path.addCurve(to: tip,
                  control1: CGPoint(x: c.x - r, y: c.y - r * 0.7), control2: CGPoint(x: c.x - r * 0.2, y: tip.y + r * 0.55))
    path.closeSubpath()
    return path
  }

  // MARK: Menu bar glyph

  /// The monochrome menu-bar mark in black on clear, for a template image: the island, a drop
  /// falling from it and the liquid's wave below. `ctx` covers `points × points` at any scale.
  static func drawGlyph(in ctx: CGContext, points: CGFloat) {
    ctx.saveGState()
    ctx.translateBy(x: 0, y: points)
    ctx.scaleBy(x: points / 18, y: -points / 18)
    ctx.setFillColor(rgb(0x000000))
    ctx.setStrokeColor(rgb(0x000000))
    ctx.addPath(CGPath(roundedRect: CGRect(x: 2.5, y: 2.25, width: 13, height: 4.5), cornerWidth: 2.25, cornerHeight: 2.25, transform: nil))
    ctx.fillPath()
    ctx.addPath(teardrop(centre: CGPoint(x: 9, y: 10.9), radius: 1.6, height: 2.05))
    ctx.fillPath()
    let wave = CGMutablePath()
    wave.move(to: CGPoint(x: 1.5, y: 15))
    wave.addCurve(to: CGPoint(x: 9, y: 14.2), control1: CGPoint(x: 4, y: 12.6), control2: CGPoint(x: 6.5, y: 12.6))
    wave.addCurve(to: CGPoint(x: 16.5, y: 15), control1: CGPoint(x: 11.5, y: 15.8), control2: CGPoint(x: 14, y: 15.8))
    ctx.addPath(wave)
    ctx.setLineWidth(1.7)
    ctx.setLineCap(.round)
    ctx.strokePath()
    ctx.restoreGState()
  }

  // MARK: Helpers

  static func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
  }

  private static func linear(_ ctx: CGContext, _ colors: [CGColor], locations: [CGFloat]? = nil, from: CGPoint, to: CGPoint) {
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
      let gradient = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: locations)
    else { return }
    ctx.drawLinearGradient(gradient, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
  }

  private static func radial(_ ctx: CGContext, _ colors: [CGColor], centre: CGPoint, radius: CGFloat) {
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
      let gradient = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: nil)
    else { return }
    ctx.drawRadialGradient(gradient, startCenter: centre, startRadius: 0, endCenter: centre, endRadius: radius,
                           options: [.drawsAfterEndLocation])
  }
}
