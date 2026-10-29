// StatsHistory.swift
// Brim
//
// Ring buffers of recent System Stats samples (Superstats-style mini graphs) plus the sparkline
// that draws them. The buffer logic is pure so it can be tested.

import SwiftUI

struct StatsHistory: Equatable {
  static let capacity = 60

  private(set) var cpu: [Double] = []
  private(set) var memory: [Double] = []
  private(set) var gpu: [Double] = []
  private(set) var networkDown: [Double] = []
  private(set) var networkUp: [Double] = []

  /// Appends one sample; unavailable readings (no GPU) are skipped, never faked as zero.
  mutating func record(cpu: Double?, memory: Double, gpu: Double?, down: Double, up: Double) {
    Self.append(&self.cpu, cpu)
    Self.append(&self.memory, memory)
    Self.append(&self.gpu, gpu)
    Self.append(&networkDown, max(0, down))
    Self.append(&networkUp, max(0, up))
  }

  private static func append(_ buffer: inout [Double], _ value: Double?) {
    guard let value else { return }
    buffer.append(value)
    if buffer.count > capacity { buffer.removeFirst(buffer.count - capacity) }
  }

  /// Samples scaled to 0...1 for drawing. Percent-style cards use their natural range;
  /// network scales to the busiest sample in the window (never below `floorBytes`, so idle stays flat).
  func series(for card: StatsCard, floorBytes: Double = 100_000) -> [Double] {
    switch card {
    case .cpu: return cpu.map(Self.clamp)
    case .ram: return memory.map(Self.clamp)
    case .gpu: return gpu.map(Self.clamp)
    case .network: return Self.scaled(zip(networkDown, networkUp).map { $0 + $1 }, floor: floorBytes)
    case .disk, .battery, .thermal: return []
    }
  }

  static func scaled(_ values: [Double], floor: Double) -> [Double] {
    let peak = max(floor, values.max() ?? 0)
    return values.map { clamp($0 / peak) }
  }

  private static func clamp(_ value: Double) -> Double { min(1, max(0, value)) }
}

/// A filled line chart without axes, sized by its frame.
struct StatsSparkline: View {
  let values: [Double]
  let tint: Color

  var body: some View {
    Canvas { context, size in
      guard values.count > 1 else { return }
      let step = size.width / CGFloat(values.count - 1)
      var line = Path()
      for (index, value) in values.enumerated() {
        let point = CGPoint(x: CGFloat(index) * step, y: size.height * (1 - CGFloat(value)))
        index == 0 ? line.move(to: point) : line.addLine(to: point)
      }
      var fill = line
      fill.addLine(to: CGPoint(x: size.width, y: size.height))
      fill.addLine(to: CGPoint(x: 0, y: size.height))
      fill.closeSubpath()
      context.fill(fill, with: .linearGradient(
        Gradient(colors: [tint.opacity(0.35), tint.opacity(0)]), startPoint: .zero,
        endPoint: CGPoint(x: 0, y: size.height)))
      context.stroke(line, with: .color(tint), style: StrokeStyle(lineWidth: 1.3, lineJoin: .round))
    }
    .accessibilityHidden(true)
  }
}
