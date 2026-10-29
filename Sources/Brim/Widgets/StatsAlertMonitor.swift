import Foundation
import SwiftUI

/// Watches CPU, memory pressure, temperature and disk space and flashes the island
/// for the alerts the user turned on. Runs only while at least one alert is enabled.
@MainActor
final class StatsAlertMonitor {
  static let shared = StatsAlertMonitor()
  private var policy = StatsAlertPolicy()
  private var timer: Timer?
  private var pressure: DispatchSourceMemoryPressure?
  private var attached = false
  private let stats: SystemStatsModel
  private let flashes: IslandFlashCenter
  private let settings: AppSettings

  init(stats: SystemStatsModel? = nil, flashes: IslandFlashCenter? = nil, settings: AppSettings = .shared) {
    self.stats = stats ?? .shared
    self.flashes = flashes ?? .shared
    self.settings = settings
  }

  var enabledKinds: Set<StatsAlertPolicy.Kind> {
    var kinds: Set<StatsAlertPolicy.Kind> = []
    if settings.statsAlertCPU { kinds.insert(.highCPU) }
    if settings.statsAlertMemory { kinds.insert(.memoryPressure) }
    if settings.statsAlertTemperature { kinds.insert(.highTemperature) }
    if settings.statsAlertDisk { kinds.insert(.lowDisk) }
    return kinds
  }

  /// Call at launch and after any alert toggle changes.
  func settingsChanged() {
    let kinds = enabledKinds
    guard !kinds.isEmpty else { return stop() }
    if !attached {
      attached = true
      stats.attach()
    }
    timer?.invalidate()
    timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.check() }
    }
    if kinds.contains(.memoryPressure) { startPressureSource() } else { stopPressureSource() }
  }

  func stop() {
    timer?.invalidate()
    timer = nil
    stopPressureSource()
    if attached {
      attached = false
      stats.detach()
    }
  }

  private func check() {
    let sample = StatsAlertPolicy.Sample(
      cpu: stats.cpu, hasCPUReading: stats.hasCPUReading, thermal: ProcessInfo.processInfo.thermalState,
      diskFree: stats.diskFree, diskTotal: stats.diskTotal)
    for kind in policy.evaluate(sample, enabled: enabledKinds, now: .now) { show(kind) }
  }

  private func startPressureSource() {
    guard pressure == nil else { return }
    let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
    source.setEventHandler { [weak self] in
      MainActor.assumeIsolated { self?.memoryPressureEvent() }
    }
    source.resume()
    pressure = source
  }

  private func stopPressureSource() {
    pressure?.cancel()
    pressure = nil
  }

  private func memoryPressureEvent() {
    if policy.memoryPressure(enabled: enabledKinds, now: .now) { show(.memoryPressure) }
  }

  private func show(_ kind: StatsAlertPolicy.Kind) {
    let alert = Self.message(for: kind, stats: stats)
    flashes.show(alert.title, symbol: alert.symbol, tint: alert.tint, duration: 3.2)
  }

  static func message(for kind: StatsAlertPolicy.Kind, stats: SystemStatsModel) -> (title: String, symbol: String, tint: Color) {
    switch kind {
    case .highCPU: return ("High CPU \(Int((stats.cpu * 100).rounded()))%", "cpu", .orange)
    case .memoryPressure: return ("Memory pressure", "memorychip", .orange)
    case .highTemperature: return ("Mac running hot", "thermometer.high", .red)
    case .lowDisk:
      let free = ByteCountFormatter.string(fromByteCount: stats.diskFree, countStyle: .file)
      return ("Low disk \(free)", "internaldrive", .yellow)
    }
  }
}
