import SwiftUI

/// Slow, looping camera drift for a still cover. Apple Music's animated covers and Spotify
/// Canvas come from undocumented endpoints, so the honest fallback is gentle motion on the
/// static artwork: a slow zoom and pan, different for every song.
enum KenBurns {
  struct Frame: Equatable {
    var scale: CGFloat
    /// Fractions of the view size; bounded so the zoomed image always covers the frame.
    var offsetX: CGFloat
    var offsetY: CGFloat
  }

  static let period: TimeInterval = 24
  static let maxScale: CGFloat = 1.12

  /// Deterministic per-song phase in 0..<1 (FNV-1a, so it is stable across launches).
  static func phase(for key: String) -> Double {
    var hash: UInt64 = 0xcbf29ce484222325
    for byte in key.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
    return Double(hash % 10_000) / 10_000
  }

  static func frame(at time: TimeInterval, seed: Double = 0) -> Frame {
    guard time.isFinite else { return Frame(scale: 1.04, offsetX: 0, offsetY: 0) }
    let t = (time / period + seed).truncatingRemainder(dividingBy: 1) * 2 * .pi
    let breathe = (1 - cos(t)) / 2                       // 0...1...0, smooth loop
    let scale = 1.04 + (maxScale - 1.04) * CGFloat(breathe)
    // A pan cannot exceed what the zoom hides: (scale - 1) / 2 on each side.
    let room = (scale - 1) / 2
    return Frame(scale: scale, offsetX: room * CGFloat(sin(t * 0.5 + seed * 6)),
                 offsetY: room * CGFloat(cos(t * 0.5 + seed * 3)))
  }
}

extension View {
  /// Ken Burns drift while `active`; static (and cheap) otherwise.
  func kenBurns(active: Bool, seed key: String) -> some View { modifier(KenBurnsModifier(active: active, key: key)) }
}

private struct KenBurnsModifier: ViewModifier {
  let active: Bool
  let key: String
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func body(content: Content) -> some View {
    if active, !reduceMotion, AppSettings.shared.mediaMotionArtwork {
      TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
        let frame = KenBurns.frame(at: context.date.timeIntervalSinceReferenceDate, seed: KenBurns.phase(for: key))
        GeometryReader { proxy in
          content.scaleEffect(frame.scale)
            .offset(x: frame.offsetX * proxy.size.width, y: frame.offsetY * proxy.size.height)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
      }
    } else {
      content
    }
  }
}
