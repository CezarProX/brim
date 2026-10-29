import SwiftUI

/// What one System Stats card shows, computed from a stats snapshot.
struct StatsCardReading: Equatable {
  let card: StatsCard
  /// 0...1 for the ring; nil for cards without a single level (network).
  let level: Double?
  let center: String
  let detail: String
  let symbol: String
  let tint: Color

  struct Input {
    var cpu = 0.0
    var memoryUsed: UInt64 = 0
    var memoryTotal: UInt64 = 1
    var gpu: Double?
    var diskFree: Int64 = 0
    var diskTotal: Int64 = 1
    var networkDown = 0.0
    var networkUp = 0.0
    var batteryPercent: Int?
    var batteryCharging = false
    var thermal: ProcessInfo.ThermalState = .nominal
  }

  static func percent(_ value: Double) -> String { "\(Int((min(1, max(0, value)) * 100).rounded()))%" }

  static func make(_ card: StatsCard, _ input: Input) -> StatsCardReading {
    func bytes(_ value: Int64) -> String { ByteCountFormatter.string(fromByteCount: value, countStyle: .file) }
    switch card {
    case .cpu:
      return .init(card: card, level: input.cpu, center: percent(input.cpu), detail: "Processor",
                   symbol: "cpu", tint: .teal)
    case .ram:
      let level = Double(input.memoryUsed) / Double(max(1, input.memoryTotal))
      let used = ByteCountFormatter.string(fromByteCount: Int64(input.memoryUsed), countStyle: .memory)
      return .init(card: card, level: level, center: percent(level), detail: used + " used",
                   symbol: "memorychip", tint: .purple)
    case .gpu:
      guard let gpu = input.gpu else {
        return .init(card: card, level: nil, center: "–", detail: "Not available", symbol: "display", tint: .pink)
      }
      return .init(card: card, level: gpu, center: percent(gpu), detail: "Graphics", symbol: "display", tint: .pink)
    case .disk:
      let level = 1 - Double(input.diskFree) / Double(max(1, input.diskTotal))
      return .init(card: card, level: level, center: percent(level), detail: bytes(input.diskFree) + " free",
                   symbol: "internaldrive", tint: .orange)
    case .network:
      return .init(card: card, level: nil, center: NetworkMath.format(input.networkDown),
                   detail: NetworkMath.format(input.networkUp), symbol: "arrow.up.arrow.down", tint: .blue)
    case .battery:
      guard let percent = input.batteryPercent else {
        return .init(card: card, level: nil, center: "–", detail: "No battery", symbol: "powerplug", tint: .green)
      }
      return .init(card: card, level: Double(percent) / 100, center: "\(percent)%",
                   detail: input.batteryCharging ? "Charging" : "On battery",
                   symbol: input.batteryCharging ? "bolt.fill" : "battery.100percent",
                   tint: percent <= 20 && !input.batteryCharging ? .red : .green)
    case .thermal:
      let hot = input.thermal == .serious || input.thermal == .critical
      return .init(card: card, level: input.thermal.statsLevel, center: input.thermal.statsLabel,
                   detail: "Thermal state", symbol: hot ? "thermometer.high" : "thermometer.medium",
                   tint: hot ? .red : (input.thermal == .fair ? .yellow : .mint))
    }
  }
}

/// The System Stats widget: two user-chosen cards side by side.
@MainActor
struct StatsWidgetView: View {
  @ObservedObject var stats: SystemStatsModel = .shared
  var left: StatsCard = AppSettings.shared.statsLeftCard
  var right: StatsCard = AppSettings.shared.statsRightCard
  /// The Home shelf stretches both cards to its row height; elsewhere they hug their content.
  var fillsHeight = false

  var body: some View {
    let input = StatsCardReading.Input(
      cpu: stats.cpu, memoryUsed: stats.memoryUsed, memoryTotal: stats.memoryTotal, gpu: stats.gpu,
      diskFree: stats.diskFree, diskTotal: stats.diskTotal, networkDown: stats.networkDown,
      networkUp: stats.networkUp, batteryPercent: stats.batteryPercent,
      batteryCharging: stats.batteryCharging, thermal: stats.thermalState)
    HStack(spacing: 8) {
      StatsCardView(reading: .make(left, input), history: stats.history.series(for: left))
      StatsCardView(reading: .make(right, input), history: stats.history.series(for: right))
    }
    .fixedSize(horizontal: false, vertical: !fillsHeight)
    .onAppear { stats.attach() }
    .onDisappear { stats.detach() }
  }
}

struct StatsCardView: View {
  let reading: StatsCardReading
  /// Recent samples scaled 0...1; empty hides the graph.
  var history: [Double] = []
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    VStack(spacing: 6) {
      Group {
        if let level = reading.level {
          ZStack {
            IslandRing(progress: level, tint: reading.tint, lineWidth: 5)
            VStack(spacing: 0) {
              Image(systemName: reading.symbol).font(.system(size: 9, weight: .bold)).foregroundStyle(reading.tint)
              Text(reading.center).font(.system(size: reading.center.count > 4 ? 11 : 14, weight: .semibold, design: .rounded))
                .monospacedDigit().contentTransition(.numericText()).minimumScaleFactor(0.7).lineLimit(1)
            }
          }
          .frame(width: 62, height: 62)
        } else if reading.card == .network {
          VStack(alignment: .leading, spacing: 5) {
            rate("arrow.down", reading.center)
            rate("arrow.up", reading.detail)
          }
          .frame(width: 80, height: 62, alignment: .leading)
        } else {
          VStack(spacing: 2) {
            Image(systemName: reading.symbol).font(.system(size: 20, weight: .semibold)).foregroundStyle(reading.tint)
            Text(reading.center).font(.system(size: 14, weight: .semibold, design: .rounded))
          }
          .frame(width: 62, height: 62)
        }
      }
      VStack(spacing: 1) {
        Text(reading.card.title).font(IslandFont.label.weight(.semibold))
        if reading.card != .network {
          Text(reading.detail).font(IslandFont.caption).foregroundStyle(IslandInk.tertiary).lineLimit(1)
        }
      }
      if history.count > 2 {
        StatsSparkline(values: history, tint: reading.tint).frame(height: 16).padding(.horizontal, 10)
          .transition(.opacity)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(.vertical, 8)
    .glassCard(radius: IslandRadius.medium)
    .animation(reduceMotion ? nil : .spring(duration: 0.4, bounce: 0), value: reading.level)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(reading.card.title) \(reading.center)")
  }

  private func rate(_ symbol: String, _ text: String) -> some View {
    HStack(spacing: 4) {
      Image(systemName: symbol).font(.system(size: 9, weight: .bold)).foregroundStyle(reading.tint)
      Text(text).font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit().lineLimit(1)
        .minimumScaleFactor(0.7)
    }
  }
}
