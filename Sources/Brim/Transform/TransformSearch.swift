import Foundation
import CoreGraphics

/// Finds the best quality (then resolution) that fits a size budget.
/// The encoder is injected so the search is testable without real images.
enum TransformSearch {
  struct Attempt: Equatable {
    var quality: Double
    var scale: Double
    var bytes: Int
    var fits: Bool
  }

  static let scales: [Double] = [1, 0.85, 0.7, 0.55, 0.4, 0.3, 0.2]
  static let qualityRange: ClosedRange<Double> = 0.1...0.95

  /// For each scale, binary-searches the highest quality whose size is within `target`.
  /// Falls to a smaller scale only when even the lowest quality is too big. When nothing
  /// fits, returns the smallest attempt (`fits == false`).
  static func fit(
    target: Int, iterations: Int = 7,
    encode: (_ quality: Double, _ scale: Double) throws -> Int
  ) rethrows -> Attempt {
    var smallest: Attempt?
    for scale in scales {
      let lowest = try encode(qualityRange.lowerBound, scale)
      let floor = Attempt(quality: qualityRange.lowerBound, scale: scale, bytes: lowest, fits: lowest <= target)
      if smallest == nil || lowest < smallest!.bytes { smallest = floor }
      guard lowest <= target else { continue }
      var best = floor
      let top = try encode(qualityRange.upperBound, scale)
      if top <= target {
        return Attempt(quality: qualityRange.upperBound, scale: scale, bytes: top, fits: true)
      }
      var low = qualityRange.lowerBound, high = qualityRange.upperBound
      for _ in 0..<iterations {
        let mid = (low + high) / 2
        let size = try encode(mid, scale)
        if size <= target {
          best = Attempt(quality: mid, scale: scale, bytes: size, fits: true)
          low = mid
        } else {
          high = mid
        }
      }
      return best
    }
    return smallest ?? Attempt(quality: qualityRange.lowerBound, scale: scales.last ?? 1, bytes: 0, fits: false)
  }
}

/// GIF frame timing. GIF delays are whole hundredths of a second, so the real frame
/// rate is rounded; very long clips lose frame rate instead of exceeding the frame cap.
enum GIFTiming {
  static let maximumFrames = 300
  static let minimumDelay = 0.02

  struct Plan: Equatable {
    var times: [Double]
    /// Delay written into the file, in seconds (a multiple of 0.01).
    var delay: Double
  }

  static func plan(duration: Double, fps: Double, maxFrames: Int = maximumFrames) -> Plan {
    guard duration > 0, fps > 0 else { return Plan(times: [0], delay: 0.1) }
    var rate = min(fps, 50)
    if duration * rate > Double(maxFrames) { rate = Double(maxFrames) / duration }
    let count = max(1, min(maxFrames, Int((duration * rate).rounded(.down))))
    let step = 1 / rate
    let times = (0..<count).map { min(Double($0) * step, max(0, duration - 0.001)) }
    let delay = max(minimumDelay, (step * 100).rounded() / 100)
    return Plan(times: times, delay: delay)
  }

  /// Output size that fits `width` while keeping aspect ratio; never enlarges.
  static func outputSize(source: CGSize, maxWidth: Int) -> CGSize {
    guard source.width > 0, source.height > 0 else { return .zero }
    let width = min(CGFloat(maxWidth), source.width)
    return CGSize(width: width.rounded(), height: (width * source.height / source.width).rounded())
  }
}
