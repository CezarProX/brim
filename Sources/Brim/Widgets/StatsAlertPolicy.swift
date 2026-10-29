import Foundation

/// When a System Stats alert may fire. Pure value logic so thresholds and rate limits are testable.
struct StatsAlertPolicy: Equatable {
  enum Kind: String, CaseIterable, Sendable { case highCPU, memoryPressure, highTemperature, lowDisk }

  struct Thresholds: Equatable {
    var cpu = 0.9
    var cpuSustain: TimeInterval = 10
    var lowDiskBytes: Int64 = 10_000_000_000
    /// The same alert never fires twice inside this window.
    var cooldown: TimeInterval = 600
  }

  struct Sample: Equatable {
    var cpu: Double
    var hasCPUReading = true
    var thermal: ProcessInfo.ThermalState
    var diskFree: Int64
    /// Zero or negative means the disk size is unknown; never alert on that.
    var diskTotal: Int64
  }

  var thresholds = Thresholds()
  private var cpuAboveSince: Date?
  private var lastFired: [Kind: Date] = [:]
  private var thermalWasHot = false
  private var diskWasLow = false

  init(thresholds: Thresholds = Thresholds()) { self.thresholds = thresholds }

  /// Alerts to show for this sample, honoring which kinds the user enabled.
  mutating func evaluate(_ sample: Sample, enabled: Set<Kind>, now: Date) -> [Kind] {
    var fired: [Kind] = []
    // CPU: sustained, and re-armed only after usage drops below the threshold.
    if sample.hasCPUReading, sample.cpu > thresholds.cpu {
      let since = cpuAboveSince ?? now
      cpuAboveSince = since
      if now.timeIntervalSince(since) >= thresholds.cpuSustain, enabled.contains(.highCPU), allow(.highCPU, now) {
        fired.append(.highCPU)
      }
    } else {
      cpuAboveSince = nil
    }
    // Temperature: on the way into serious/critical.
    let hot = sample.thermal == .serious || sample.thermal == .critical
    if hot, !thermalWasHot, enabled.contains(.highTemperature), allow(.highTemperature, now) {
      fired.append(.highTemperature)
    }
    thermalWasHot = hot
    // Disk: on the way below the limit.
    let low = sample.diskTotal > 0 && sample.diskFree < thresholds.lowDiskBytes
    if low, !diskWasLow, enabled.contains(.lowDisk), allow(.lowDisk, now) { fired.append(.lowDisk) }
    diskWasLow = low
    return fired
  }

  /// Memory pressure arrives as an event rather than a sample.
  mutating func memoryPressure(enabled: Set<Kind>, now: Date) -> Bool {
    enabled.contains(.memoryPressure) && allow(.memoryPressure, now)
  }

  /// Records the firing when the cooldown has passed.
  private mutating func allow(_ kind: Kind, _ now: Date) -> Bool {
    if let last = lastFired[kind], now.timeIntervalSince(last) < thresholds.cooldown { return false }
    lastFired[kind] = now
    return true
  }
}
