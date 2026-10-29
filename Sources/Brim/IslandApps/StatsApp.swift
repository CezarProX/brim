import AppKit
import SwiftUI

/// System Stats, opened: three Activity Monitor-style gauges with their recent history, a status row
/// (network, graphics, battery, temperature) and a shortcut to Activity Monitor for the detail.
struct StatsAppView: View {
  @ObservedObject var model: SystemStatsModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  /// Rings turn red when a resource is nearly used up.
  static func tint(_ base: Color, level: Double?) -> Color { (level ?? 0) >= 0.9 ? .red : base }

  var body: some View {
    let memory = Double(model.memoryUsed) / Double(max(1, model.memoryTotal))
    let disk = model.diskTotal > 0 ? 1 - Double(model.diskFree) / Double(model.diskTotal) : nil
    VStack(spacing: IslandSpace.s) {
      HStack(spacing: IslandSpace.s) {
        gaugeCard(
          title: "CPU", symbol: "cpu", level: model.hasCPUReading ? model.cpu : nil, base: .teal,
          detail: model.hasCPUReading
            ? L10n.tr("%lld cores", ProcessInfo.processInfo.activeProcessorCount) : L10n.tr("Measuring…"),
          history: model.history.series(for: .cpu))
        gaugeCard(
          title: "Memory", symbol: "memorychip", level: model.memoryTotal > 0 ? memory : nil, base: .purple,
          detail: L10n.tr("%@ of %@", compact(model.memoryUsed), compact(model.memoryTotal)),
          history: model.history.series(for: .ram))
        gaugeCard(
          title: "Disk", symbol: "internaldrive", level: disk, base: .orange,
          detail: L10n.tr("%@ free", bytes(model.diskFree, .file)), history: [])
      }
      statusRow
      HStack {
        Spacer(minLength: 0)
        IslandAppButton(title: L10n.tr("Open Activity Monitor"), symbol: "chart.bar.xaxis") { Self.openActivityMonitor() }
          .frame(width: 210)
      }
    }
    .frame(maxWidth: .infinity)
    .onAppear { model.attach() }
    .onDisappear { model.detach() }
  }

  static func openActivityMonitor() {
    let url = URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
    NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
  }

  /// "19.4 GB" without the repeated unit noise of two full byte strings.
  private func compact(_ value: UInt64) -> String {
    String(format: "%.1f GB", Double(value) / 1_073_741_824)
  }

  private func bytes(_ value: Int64, _ style: ByteCountFormatter.CountStyle) -> String {
    ByteCountFormatter.string(fromByteCount: value, countStyle: style)
  }

  // MARK: Gauges

  private func gaugeCard(title: String, symbol: String, level: Double?, base: Color, detail: String,
                         history: [Double]) -> some View {
    let tint = Self.tint(base, level: level)
    return VStack(spacing: 6) {
      HStack(spacing: 10) {
        ZStack {
          IslandRing(progress: level ?? 0, tint: tint, lineWidth: 6).padding(3)
          Text(level.map { StatsCardReading.percent($0) } ?? "–")
            .font(.system(size: 14, weight: .semibold, design: .rounded)).monospacedDigit()
            .minimumScaleFactor(0.7).lineLimit(1)
            .contentTransition(.numericText())
        }
        .frame(width: 48, height: 48)
        VStack(alignment: .leading, spacing: 2) {
          Label(L10n.tr(title), systemImage: symbol).font(.system(size: 13, weight: .semibold))
            .labelStyle(StatsLabelStyle(tint: tint)).lineLimit(1).minimumScaleFactor(0.8)
          Text(detail).font(.system(size: 12)).foregroundStyle(IslandInk.secondary)
            .lineLimit(2).minimumScaleFactor(0.85).fixedSize(horizontal: false, vertical: true)
        }
        Spacer(minLength: 0)
      }
      if history.count > 2 {
        StatsSparkline(values: history, tint: tint).frame(height: 16)
      } else {
        Color.clear.frame(height: 16)
      }
    }
    .padding(.horizontal, 10).padding(.vertical, 8)
    .frame(maxWidth: .infinity)
    .islandAppCard()
    .animation(reduceMotion ? nil : .spring(duration: 0.4, bounce: 0), value: level)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(L10n.tr(title))
    .accessibilityValue(level.map { StatsCardReading.percent($0) + ", " + detail } ?? detail)
  }

  // MARK: Status row

  private var statusRow: some View {
    HStack(spacing: IslandSpace.s) {
      chip(symbol: "arrow.down", tint: .blue, text: NetworkMath.format(model.networkDown),
           trailingSymbol: "arrow.up", trailingText: NetworkMath.format(model.networkUp), label: "Network")
        .layoutPriority(1)
      if let gpu = model.gpu {
        chip(symbol: "display", tint: .pink, text: StatsCardReading.percent(gpu), label: "GPU")
      }
      if let percent = model.batteryPercent {
        chip(symbol: model.batteryCharging ? "bolt.fill" : "battery.75percent",
             tint: percent <= 20 && !model.batteryCharging ? .red : .green, text: "\(percent)%", label: "Battery")
      }
      let thermal = model.thermalState
      chip(symbol: thermal == .nominal || thermal == .fair ? "thermometer.medium" : "thermometer.high",
           tint: thermal == .nominal ? .mint : (thermal == .fair ? .yellow : .red), text: thermal.statsLabel,
           label: "Temperature")
    }
  }

  private func chip(symbol: String, tint: Color, text: String, trailingSymbol: String? = nil,
                    trailingText: String? = nil, label: String) -> some View {
    HStack(spacing: 5) {
      Image(systemName: symbol).font(.system(size: 12, weight: .bold)).foregroundStyle(tint)
      Text(text).font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit().lineLimit(1)
        .contentTransition(.numericText())
      if let trailingSymbol, let trailingText {
        Image(systemName: trailingSymbol).font(.system(size: 12, weight: .bold)).foregroundStyle(tint)
          .padding(.leading, 4)
        Text(trailingText).font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit().lineLimit(1)
          .contentTransition(.numericText())
      }
    }
    .padding(.horizontal, 10)
    .frame(minHeight: 32)
    .fixedSize(horizontal: true, vertical: false)
    .frame(maxWidth: trailingText == nil ? nil : .infinity)
    .islandAppCard(radius: 10)
    .accessibilityElement(children: .ignore)
    .help(L10n.tr(label))
    .accessibilityLabel(L10n.tr(label))
    .accessibilityValue([text, trailingText].compactMap { $0 }.joined(separator: ", "))
  }
}

private struct StatsLabelStyle: LabelStyle {
  let tint: Color
  func makeBody(configuration: Configuration) -> some View {
    HStack(spacing: 5) {
      configuration.icon.font(.system(size: 11, weight: .semibold)).foregroundStyle(tint)
      configuration.title
    }
  }
}
