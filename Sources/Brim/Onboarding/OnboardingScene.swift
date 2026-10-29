import AppKit
import SwiftUI

/// The generated layers of the tour's night scene, built once.
final class OnboardingArt: @unchecked Sendable {
  struct Layer {
    let image: CGImage
    let depth: Double
    let size: CGSize
  }

  static let shared = OnboardingArt()
  /// Back to front.
  let layers: [Layer]

  private init() {
    typealias G = OnboardingArtGenerator
    let ridge = G.ridge(), land = G.land()
    let ordered: [(PixelLayer, Double)] = [
      (G.sky(), G.Depth.sky), (G.sea(), G.Depth.sky),
      (G.reflection(of: ridge, strength: 0.7), G.Depth.ridge), (G.reflection(of: land, strength: 0.8), G.Depth.land),
      (G.clouds(), G.Depth.clouds), (ridge, G.Depth.ridge), (land, G.Depth.land),
    ]
    layers = ordered.compactMap { layer, depth in
      layer.cgImage().map { Layer(image: $0, depth: depth, size: CGSize(width: layer.width * G.cell, height: layer.height * G.cell)) }
    }
  }

  static var panPoints: CGFloat { CGFloat(OnboardingArtGenerator.pan * OnboardingArtGenerator.cell) }
  static let size = CGSize(
    width: OnboardingArtGenerator.gridWidth * OnboardingArtGenerator.cell,
    height: OnboardingArtGenerator.gridHeight * OnboardingArtGenerator.cell)

  /// The scene flattened at a pan position (0...1), for the glass to blur.
  func composite(progress: Double) -> NSImage? {
    let size = Self.size
    guard let context = CGContext(
      data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    context.interpolationQuality = .none
    for layer in layers {
      let x = -progress * Self.panPoints * layer.depth
      context.draw(layer.image, in: CGRect(x: x, y: size.height - layer.size.height, width: layer.size.width, height: layer.size.height))
    }
    return context.makeImage().map { NSImage(cgImage: $0, size: size) }
  }
}

/// The illustration: parallax layers that drift as the tour advances, and stars that twinkle.
struct OnboardingScene: View {
  /// 0 at the first page, 1 at the last.
  var progress: Double
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    ZStack(alignment: .topLeading) {
      Color(red: 0.02, green: 0.03, blue: 0.14)
      ForEach(Array(OnboardingArt.shared.layers.enumerated()), id: \.offset) { _, layer in
        Image(decorative: layer.image, scale: 1).resizable().interpolation(.none)
          .frame(width: layer.size.width, height: layer.size.height)
          .offset(x: -progress * OnboardingArt.panPoints * layer.depth)
      }
      Twinkles(progress: progress, animated: !reduceMotion)
    }
    .frame(width: OnboardingArt.size.width, height: OnboardingArt.size.height, alignment: .topLeading)
    .clipped()
    .animation(reduceMotion ? nil : .spring(duration: 0.9, bounce: 0.06), value: progress)
    .accessibilityHidden(true)
  }
}

/// Four-point sparkles with a slow pulse, over the baked stars.
private struct Twinkles: View {
  let progress: Double
  let animated: Bool
  private static let spots: [(x: Double, y: Double, phase: Double, size: Double)] = [
    (0.08, 0.30, 0.0, 7), (0.30, 0.52, 1.7, 6), (0.62, 0.40, 3.1, 8), (0.91, 0.22, 4.4, 5), (0.15, 0.10, 2.3, 5),
    (0.46, 0.16, 5.2, 6), (0.75, 0.12, 0.9, 5), (0.97, 0.52, 3.8, 6),
  ]

  var body: some View {
    TimelineView(.animation(minimumInterval: 1.0 / 24, paused: !animated)) { timeline in
      Canvas { context, size in
        let time = timeline.date.timeIntervalSinceReferenceDate
        let drift = -progress * OnboardingArt.panPoints * OnboardingArtGenerator.Depth.sky
        for spot in Self.spots {
          let pulse = animated ? 0.5 + 0.5 * sin(time * 1.3 + spot.phase) : 0.8
          let center = CGPoint(x: spot.x * size.width + drift, y: spot.y * size.height * 0.62)
          let arm = spot.size * (0.55 + 0.45 * pulse)
          var path = Path()
          path.move(to: CGPoint(x: center.x - arm, y: center.y)); path.addLine(to: CGPoint(x: center.x + arm, y: center.y))
          path.move(to: CGPoint(x: center.x, y: center.y - arm)); path.addLine(to: CGPoint(x: center.x, y: center.y + arm))
          context.stroke(path, with: .color(.white.opacity(0.35 + 0.5 * pulse)), lineWidth: 2)
          context.fill(Path(CGRect(x: center.x - 2, y: center.y - 2, width: 4, height: 4)), with: .color(.white.opacity(0.9)))
        }
      }
    }
  }
}
