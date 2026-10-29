import CoreGraphics
import Foundation

/// One RGBA layer of the tour's night scene, drawn at low resolution (one pixel is two points) so
/// it reads as ordered-dither pixel art when scaled up without smoothing.
struct PixelLayer {
  let width: Int
  let height: Int
  var rgba: [UInt8]

  init(width: Int, height: Int) {
    self.width = width
    self.height = height
    rgba = [UInt8](repeating: 0, count: width * height * 4)
  }

  mutating func set(_ x: Int, _ y: Int, _ color: PixelColor, alpha: Double = 1) {
    guard x >= 0, y >= 0, x < width, y < height else { return }
    let i = (y * width + x) * 4
    let a = max(0, min(1, alpha))
    rgba[i] = UInt8(max(0, min(255, color.r * a * 255)))
    rgba[i + 1] = UInt8(max(0, min(255, color.g * a * 255)))
    rgba[i + 2] = UInt8(max(0, min(255, color.b * a * 255)))
    rgba[i + 3] = UInt8(a * 255)
  }

  func pixel(_ x: Int, _ y: Int) -> (PixelColor, Double)? {
    guard x >= 0, y >= 0, x < width, y < height else { return nil }
    let i = (y * width + x) * 4
    let a = Double(rgba[i + 3]) / 255
    guard a > 0 else { return nil }
    return (PixelColor(r: Double(rgba[i]) / 255 / a, g: Double(rgba[i + 1]) / 255 / a, b: Double(rgba[i + 2]) / 255 / a), a)
  }

  func cgImage() -> CGImage? {
    let data = Data(rgba) as CFData
    guard let provider = CGDataProvider(data: data) else { return nil }
    return CGImage(
      width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider,
      decode: nil, shouldInterpolate: false, intent: .defaultIntent)
  }
}

struct PixelColor {
  var r: Double
  var g: Double
  var b: Double

  init(r: Double, g: Double, b: Double) { (self.r, self.g, self.b) = (r, g, b) }
  init(hex: UInt32) {
    r = Double((hex >> 16) & 0xFF) / 255
    g = Double((hex >> 8) & 0xFF) / 255
    b = Double(hex & 0xFF) / 255
  }

  func mixed(with other: PixelColor, _ t: Double) -> PixelColor {
    PixelColor(r: r + (other.r - r) * t, g: g + (other.g - g) * t, b: b + (other.b - b) * t)
  }
}

/// A colour ramp sampled by a 0...1 value.
struct PixelRamp {
  let stops: [(Double, PixelColor)]

  init(_ stops: [(Double, UInt32)]) { self.stops = stops.map { ($0.0, PixelColor(hex: $0.1)) } }

  func color(_ value: Double) -> PixelColor {
    let t = max(0, min(1, value))
    guard let last = stops.last, let first = stops.first else { return PixelColor(r: 0, g: 0, b: 0) }
    if t <= first.0 { return first.1 }
    for index in 1..<stops.count where t <= stops[index].0 {
      let (a, b) = (stops[index - 1], stops[index])
      return a.1.mixed(with: b.1, (t - a.0) / max(0.0001, b.0 - a.0))
    }
    return last.1
  }
}

/// Deterministic noise and the Bayer matrix the dither uses.
enum PixelMath {
  static let bayer8: [[Double]] = {
    var m: [[Int]] = [[0]]
    while m.count < 8 {
      let n = m.count
      var next = [[Int]](repeating: [Int](repeating: 0, count: n * 2), count: n * 2)
      for y in 0..<n {
        for x in 0..<n {
          let v = m[y][x] * 4
          next[y][x] = v
          next[y][x + n] = v + 2
          next[y + n][x] = v + 3
          next[y + n][x + n] = v + 1
        }
      }
      m = next
    }
    return m.map { $0.map { (Double($0) + 0.5) / 64 } }
  }()

  static func threshold(_ x: Int, _ y: Int) -> Double { bayer8[((y % 8) + 8) % 8][((x % 8) + 8) % 8] }

  /// Snaps `value` to `levels` steps, choosing the neighbouring step by the Bayer threshold.
  static func dither(_ value: Double, levels: Int, x: Int, y: Int) -> Double {
    let scaled = max(0, min(1, value)) * Double(levels - 1)
    let base = scaled.rounded(.down)
    let step = scaled - base > threshold(x, y) ? base + 1 : base
    return step / Double(levels - 1)
  }

  static func hash(_ x: Int, _ y: Int, seed: Int = 0) -> Double {
    var h = UInt64(truncatingIfNeeded: x) &* 0x9E3779B97F4A7C15
    h ^= UInt64(truncatingIfNeeded: y) &* 0xC2B2AE3D27D4EB4F
    h ^= UInt64(truncatingIfNeeded: seed) &* 0x165667B19E3779F9
    h ^= h >> 29
    h = h &* 0xBF58476D1CE4E5B9
    h ^= h >> 32
    return Double(h & 0xFFFFFF) / Double(0x1000000)
  }

  static func smooth(_ t: Double) -> Double { let c = max(0, min(1, t)); return c * c * (3 - 2 * c) }

  static func smoothstep(_ a: Double, _ b: Double, _ x: Double) -> Double { smooth((x - a) / (b - a)) }

  static func valueNoise(_ x: Double, _ y: Double, seed: Int) -> Double {
    let (xi, yi) = (Int(x.rounded(.down)), Int(y.rounded(.down)))
    let (fx, fy) = (smooth(x - Double(xi)), smooth(y - Double(yi)))
    let a = hash(xi, yi, seed: seed), b = hash(xi + 1, yi, seed: seed)
    let c = hash(xi, yi + 1, seed: seed), d = hash(xi + 1, yi + 1, seed: seed)
    return (a + (b - a) * fx) + ((c + (d - c) * fx) - (a + (b - a) * fx)) * fy
  }

  static func fbm(_ x: Double, _ y: Double, seed: Int, octaves: Int = 4) -> Double {
    var sum = 0.0, amplitude = 0.5, frequency = 1.0, norm = 0.0
    for octave in 0..<octaves {
      sum += valueNoise(x * frequency, y * frequency, seed: seed &+ octave * 31) * amplitude
      norm += amplitude
      amplitude *= 0.5
      frequency *= 2
    }
    return sum / norm
  }
}

/// Draws the tour's illustration: a night sky with a moon, stars, cloud banks, two mountain ridges, a
/// lighthouse island with cypresses, and a sea that mirrors them. Everything is procedural.
enum OnboardingArtGenerator {
  /// Grid cell size in points.
  static let cell = 2
  static let gridWidth = 400
  static let gridHeight = 380
  /// Where sky meets sea, in grid pixels.
  static let horizon = 250
  /// Largest horizontal drift (grid pixels) the front layer moves across the whole tour.
  static let pan = 110
  static let moon = (x: 318.0, y: 86.0, radius: 27.0)

  /// Parallax factor per layer: far things drift less.
  enum Depth {
    static let sky = 0.2, clouds = 0.5, ridge = 0.7, land = 1.0
  }

  static func width(for depth: Double) -> Int { gridWidth + Int((Double(pan) * depth).rounded(.up)) + 2 }

  // MARK: Sky

  static let skyRamp = PixelRamp([
    (0, 0x04051C), (0.16, 0x0A0F4E), (0.36, 0x1A1FA6), (0.54, 0x3636E2), (0.68, 0x6A4FEC),
    (0.8, 0xB86BDD), (0.9, 0xF2A6C0), (1, 0xFFF1E4),
  ])

  static func sky() -> PixelLayer {
    let w = width(for: Depth.sky)
    var layer = PixelLayer(width: w, height: gridHeight)
    let hy = Double(horizon)
    let moonX = moon.x + Double(w - gridWidth) * 0.0
    for y in 0..<gridHeight {
      for x in 0..<w {
        let fy = Double(y) / hy
        var v = 0.03 + 0.56 * pow(min(1.2, fy), 1.7)
        let dx = Double(x) - moonX, dy = Double(y) - moon.y
        v += 0.30 * exp(-(dx * dx + dy * dy) / (2 * 70 * 70))
        v += 0.06 * exp(-(dx * dx + dy * dy) / (2 * 150 * 150))
        v += 0.34 * exp(-pow((hy - Double(y)) / 34, 2)) * (y < horizon ? 1 : 0)
        v += (PixelMath.fbm(Double(x) * 0.03, Double(y) * 0.05, seed: 3, octaves: 3) - 0.5) * 0.06
        if y >= horizon { v = 0.5 - Double(y - horizon) / 300 }
        let q = PixelMath.dither(v, levels: 12, x: x, y: y)
        layer.set(x, y, skyRamp.color(q))
      }
    }
    drawStars(on: &layer)
    drawMoon(on: &layer, centerX: moonX)
    return layer
  }

  private static func drawStars(on layer: inout PixelLayer) {
    for index in 0..<150 {
      let x = Int(PixelMath.hash(index, 1, seed: 11) * Double(layer.width))
      let y = Int(PixelMath.hash(index, 2, seed: 11) * Double(horizon - 40) * 0.92)
      let brightness = 0.35 + PixelMath.hash(index, 3, seed: 11) * 0.65
      let fade = 1 - PixelMath.smoothstep(0.45, 0.95, Double(y) / Double(horizon))
      let tone = PixelColor(hex: 0xE7E4FF).mixed(with: PixelColor(hex: 0xFFD9E6), PixelMath.hash(index, 4, seed: 11) * 0.5)
      layer.set(x, y, tone, alpha: brightness * fade)
      if brightness > 0.9 && fade > 0.5 {
        for (ox, oy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] { layer.set(x + ox, y + oy, tone, alpha: 0.35 * fade) }
      }
    }
  }

  private static func drawMoon(on layer: inout PixelLayer, centerX: Double) {
    let r = moon.radius
    let light = (x: -0.62, y: -0.28, z: 0.73)
    for y in Int(moon.y - r - 6)...Int(moon.y + r + 6) {
      for x in Int(centerX - r - 6)...Int(centerX + r + 6) {
        let dx = Double(x) - centerX, dy = Double(y) - moon.y
        let d = (dx * dx + dy * dy).squareRoot()
        if d > r {
          // A thin bright rim of halo just outside the disc.
          if d < r + 3, let (base, _) = layer.pixel(x, y) {
            layer.set(x, y, base.mixed(with: PixelColor(hex: 0xE9E3FF), 0.35 * (1 - (d - r) / 3)))
          }
          continue
        }
        let (nx, ny) = (dx / r, dy / r)
        let nz = max(0, 1 - nx * nx - ny * ny).squareRoot()
        var lit = nx * light.x + ny * light.y + nz * light.z
        let crater = PixelMath.fbm(Double(x) * 0.22, Double(y) * 0.22, seed: 7, octaves: 3)
        lit = lit * 0.9 + (crater - 0.5) * 0.45
        let q = PixelMath.dither(lit * 1.25, levels: 6, x: x, y: y)
        let dark = PixelColor(hex: 0x2A2D8F), mid = PixelColor(hex: 0xA9A7F6), bright = PixelColor(hex: 0xFFF8EA)
        let color = q < 0.5 ? dark.mixed(with: mid, q * 2) : mid.mixed(with: bright, (q - 0.5) * 2)
        layer.set(x, y, color)
      }
    }
  }

  // MARK: Clouds

  static let cloudRamp = PixelRamp([(0, 0x13167E), (0.35, 0x3A3FD6), (0.65, 0x9A9CF8), (0.85, 0xE0DCFF), (1, 0xFFF4F0)])

  static func clouds() -> PixelLayer {
    let w = width(for: Depth.clouds)
    var layer = PixelLayer(width: w, height: gridHeight)
    func density(_ x: Int, _ y: Int) -> Double {
      let fx = Double(x), fy = Double(y)
      let band = exp(-pow((fy - 205) / 52, 2))
      let upper = 0.55 * exp(-pow((fy - 140) / 36, 2)) * PixelMath.smoothstep(0.3, 0.9, PixelMath.valueNoise(fx * 0.012, 4, seed: 9))
      let flank = 0.55 + 0.7 * max(PixelMath.smoothstep(150, 20, fx - Double(w - gridWidth) * 0.2), PixelMath.smoothstep(240, 380, fx))
      let n = PixelMath.fbm(fx * 0.02, fy * 0.055, seed: 21, octaves: 5)
      return n * 0.95 + (band * flank + upper) * 0.36 - 0.5
    }
    for y in 0..<horizon - 2 {
      for x in 0..<w {
        let d = density(x, y)
        guard d > 0.02 else { continue }
        let coverage = PixelMath.smoothstep(0.02, 0.2, d)
        guard coverage > PixelMath.threshold(x, y) else { continue }
        let shade = 0.62 + (d - density(x + 2, y + 4)) * 9
        let rise = 1 - Double(y) / Double(horizon - 2)
        let value = shade * (0.55 + 0.45 * rise) + 0.1
        let q = PixelMath.dither(value, levels: 6, x: x, y: y)
        layer.set(x, y, cloudRamp.color(q))
      }
    }
    return layer
  }

  // MARK: Ridges and land

  static let ridgeRamp = PixelRamp([(0, 0x05062A), (0.5, 0x131890), (1, 0x4A4CD8)])
  static let landRamp = PixelRamp([(0, 0x02031A), (0.55, 0x0A0D55), (1, 0x2C31B4)])

  static func ridge() -> PixelLayer {
    let w = width(for: Depth.ridge)
    var layer = PixelLayer(width: w, height: gridHeight)
    let hy = Double(horizon)
    func top(_ x: Int) -> Double {
      let fx = Double(x)
      let big = PixelMath.fbm(fx * 0.011, 2.5, seed: 41, octaves: 4)
      let craggy = PixelMath.fbm(fx * 0.05, 8, seed: 43, octaves: 3)
      let envelope = 0.45 + 0.55 * PixelMath.smoothstep(40, 140, abs(fx - Double(w) * 0.5) + 30)
      return hy - 8 - (big * 78 * envelope + craggy * 14)
    }
    for x in 0..<w {
      let edge = top(x)
      let slope = top(x + 2) - top(x - 2)
      for y in Int(edge)..<horizon {
        let depth = (Double(y) - edge) / 70
        let facing = 0.5 - slope * 0.22
        let haze = pow(Double(y) / hy, 4) * 0.5
        let grain = PixelMath.fbm(Double(x) * 0.18, Double(y) * 0.3, seed: 5, octaves: 2)
        var v = 0.2 + facing * 0.32 - depth * 0.2 + haze + (grain - 0.5) * 0.3
        if Double(y) - edge < 2 { v += 0.28 }
        layer.set(x, y, ridgeRamp.color(PixelMath.dither(v, levels: 7, x: x, y: y)))
      }
    }
    return layer
  }

  static func land() -> PixelLayer {
    let w = width(for: Depth.land)
    var layer = PixelLayer(width: w, height: gridHeight)
    let hy = Double(horizon)
    let shoreline = hy + 4
    func hill(_ fx: Double, center: Double, spread: Double, height: Double) -> Double {
      height * exp(-pow((fx - center) / spread, 2))
    }
    func top(_ x: Int) -> Double {
      let fx = Double(x)
      let leftHill = hill(fx, center: 10, spread: 82, height: 74)
      let rightHill = hill(fx, center: Double(w) - 14, spread: 74, height: 90)
      let islet = hill(fx, center: 238 + Double(w - gridWidth) * 0.55, spread: 38, height: 30)
      let rough = (PixelMath.fbm(fx * 0.08, 3, seed: 61, octaves: 3) - 0.5) * 11
      let h = max(leftHill, rightHill, islet)
      return h > 1 ? shoreline - h - rough * min(1, h / 20) : shoreline + 10
    }
    for x in 0..<w {
      let edge = top(x)
      guard edge < shoreline else { continue }
      let slope = top(x + 2) - top(x - 2)
      for y in Int(edge)..<Int(shoreline) {
        let depth = (Double(y) - edge) / 60
        let grain = PixelMath.fbm(Double(x) * 0.2, Double(y) * 0.32, seed: 17, octaves: 2)
        var v = 0.18 + (0.5 - slope * 0.2) * 0.28 - depth * 0.16 + (grain - 0.5) * 0.4
        if Double(y) - edge < 2 { v += 0.3 }
        layer.set(x, y, landRamp.color(PixelMath.dither(v, levels: 6, x: x, y: y)))
      }
    }
    let isletX = Int(238 + Double(w - gridWidth) * 0.55)
    drawLighthouse(on: &layer, baseX: isletX + 2, baseY: Int(top(isletX + 2)) + 2)
    for (cx, scale) in [(34.0, 1.0), (62.0, 0.8), (14.0, 0.7), (Double(w) - 40, 1.15), (Double(w) - 66, 0.85), (Double(w) - 18, 0.8)] {
      let base = Int(top(Int(cx))) + 3
      drawCypress(on: &layer, centerX: Int(cx), baseY: base, height: 62 * scale, seed: Int(cx))
    }
    drawCypress(on: &layer, centerX: isletX - 14, baseY: Int(top(isletX - 14)) + 2, height: 26, seed: 99)
    drawCypress(on: &layer, centerX: isletX + 20, baseY: Int(top(isletX + 20)) + 2, height: 20, seed: 98)
    return layer
  }

  private static func drawCypress(on layer: inout PixelLayer, centerX: Int, baseY: Int, height: Double, seed: Int) {
    let top = Double(baseY) - height
    for y in Int(top)...baseY {
      let t = (Double(y) - top) / height
      let half = height * 0.15 * pow(sin(min(1, t * 1.05) * .pi * 0.62 + 0.18), 1.2) * (0.55 + 0.45 * t)
      let wobble = (PixelMath.hash(y, seed, seed: 5) - 0.5) * 1.6
      let left = Int((Double(centerX) - half + wobble).rounded()), right = Int((Double(centerX) + half + wobble).rounded())
      guard left <= right else { continue }
      for x in left...right {
        let side = Double(x - left) / Double(max(1, right - left))
        let v = 0.16 + side * 0.34 + (PixelMath.hash(x, y, seed: seed) - 0.5) * 0.3
        layer.set(x, y, landRamp.color(PixelMath.dither(v, levels: 5, x: x, y: y)))
      }
    }
  }

  private static func drawLighthouse(on layer: inout PixelLayer, baseX: Int, baseY: Int) {
    let height = 50
    for step in 0..<height {
      let y = baseY - step
      let t = Double(step) / Double(height)
      let half = 5.2 - 2.4 * t
      for x in Int((Double(baseX) - half).rounded())...Int((Double(baseX) + half).rounded()) {
        let side = (Double(x) - (Double(baseX) - half)) / (half * 2)
        let band = (step / 9) % 2 == 0 ? 0.0 : 0.1
        let v = 0.2 + side * 0.5 + band
        layer.set(x, y, PixelRamp([(0, 0x0B0E5C), (0.5, 0x3C41C8), (1, 0xB9BAFF)]).color(PixelMath.dither(v, levels: 6, x: x, y: y)))
      }
    }
    // Gallery, lantern room and roof.
    let gallery = baseY - height
    for x in (baseX - 6)...(baseX + 6) { layer.set(x, gallery, PixelColor(hex: 0x14186E)) }
    for y in (gallery - 6)..<gallery {
      for x in (baseX - 3)...(baseX + 3) { layer.set(x, y, PixelColor(hex: 0xFFE9B0)) }
    }
    for y in (gallery - 10)..<(gallery - 6) {
      let half = y - (gallery - 10)
      for x in (baseX - half)...(baseX + half) { layer.set(x, y, PixelColor(hex: 0x0A0C52)) }
    }
    // Warm glow around the lamp.
    for dy in -12...12 {
      for dx in -14...14 {
        let d = Double(dx * dx + dy * dy).squareRoot()
        guard d > 4, d < 14, PixelMath.threshold(baseX + dx, gallery - 3 + dy) < (1 - d / 14) * 0.5 else { continue }
        layer.set(baseX + dx, gallery - 3 + dy, PixelColor(hex: 0xFFD79A), alpha: 0.7)
      }
    }
  }

  // MARK: Sea

  static let seaRamp = PixelRamp([(0, 0x04051F), (0.4, 0x0D1170), (0.75, 0x2B2FC9), (1, 0x7C63F0)])

  static func sea() -> PixelLayer {
    let w = width(for: Depth.sky)
    var layer = PixelLayer(width: w, height: gridHeight)
    for y in horizon..<gridHeight {
      let t = Double(y - horizon) / Double(gridHeight - horizon)
      for x in 0..<w {
        let swell = sin(Double(x) * 0.09 + Double(y) * 0.8 + PixelMath.hash(y, 3) * 6) * 0.04
        let v = 0.72 - pow(t, 0.55) * 0.7 + swell + (PixelMath.fbm(Double(x) * 0.03, Double(y) * 0.5, seed: 27, octaves: 2) - 0.5) * 0.14
        layer.set(x, y, seaRamp.color(PixelMath.dither(v, levels: 9, x: x, y: y)))
      }
    }
    // The moon's glitter path.
    let centre = moon.x
    for y in horizon..<gridHeight {
      let t = Double(y - horizon) / Double(gridHeight - horizon)
      let spread = 7 + t * 46
      let broken = PixelMath.hash(y / 2, 8, seed: 2) < 0.78 - t * 0.2
      guard broken else { continue }
      let run = Int(spread * (0.35 + PixelMath.hash(y, 4, seed: 2) * 0.65))
      let shift = Int((PixelMath.hash(y, 6, seed: 2) - 0.5) * spread * 0.7)
      for x in (Int(centre) + shift - run)...(Int(centre) + shift + run) {
        let edge = 1 - abs(Double(x - Int(centre) - shift)) / Double(max(1, run))
        guard edge * (1 - t * 0.55) > PixelMath.threshold(x, y) * 0.8 else { continue }
        layer.set(x, y, PixelColor(hex: 0xEDE6FF), alpha: 0.9 - t * 0.35)
      }
    }
    return layer
  }

  /// A rippled mirror image of `source` below the horizon.
  static func reflection(of source: PixelLayer, strength: Double) -> PixelLayer {
    var layer = PixelLayer(width: source.width, height: gridHeight)
    let depth = gridHeight - horizon
    for dy in 0..<depth {
      let t = Double(dy) / Double(depth)
      let y = horizon + dy
      // Fewer rows survive as the reflection sinks, the way ripples break it up.
      if PixelMath.hash(dy, 12, seed: 4) < 0.18 + t * 0.5 { continue }
      let sourceY = horizon - 2 - Int(Double(dy) * 0.72)
      guard sourceY >= 0 else { break }
      for x in 0..<source.width {
        let wobble = Int((sin(Double(dy) * 0.9 + Double(x) * 0.03) * (1 + t * 3)).rounded())
        guard let (color, alpha) = source.pixel(x + wobble, sourceY) else { continue }
        let tint = color.mixed(with: PixelColor(hex: 0x1B1FA0), 0.45)
        layer.set(x, y, tint, alpha: alpha * strength * (1 - t * 0.8))
      }
    }
    return layer
  }
}
