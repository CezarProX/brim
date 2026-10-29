import Darwin
import Foundation
import IOKit
import IOKit.ps

/// Network throughput math. Interface byte counters are 32-bit on Darwin and wrap.
enum NetworkMath {
  struct Counters: Equatable {
    var received: UInt64
    var sent: UInt64
  }

  /// Bytes per second between two samples; a wrapped 32-bit counter is handled, a clock jump gives 0.
  static func rates(from previous: Counters, to current: Counters, seconds: TimeInterval) -> (down: Double, up: Double) {
    guard seconds > 0.01 else { return (0, 0) }
    func delta(_ old: UInt64, _ new: UInt64) -> UInt64 {
      new >= old ? new - old : (new &+ (1 << 32)) &- old
    }
    return (Double(delta(previous.received, current.received)) / seconds,
            Double(delta(previous.sent, current.sent)) / seconds)
  }

  /// "1.2 MB/s", "340 KB/s", "0 B/s".
  static func format(_ bytesPerSecond: Double) -> String {
    let value = max(0, bytesPerSecond)
    switch value {
    case 1_000_000_000...: return String(format: "%.1f GB/s", value / 1e9)
    case 1_000_000...: return String(format: value >= 1e7 ? "%.0f MB/s" : "%.1f MB/s", value / 1e6)
    case 1000...: return String(format: "%.0f KB/s", value / 1e3)
    default: return "\(Int(value)) B/s"
    }
  }
}

/// Public-API readers for the extra System Stats cards.
enum SystemStatsReaders {
  /// Sum of bytes in/out over physical, up interfaces (loopback and tunnels excluded).
  static func networkCounters() -> NetworkMath.Counters? {
    var list: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&list) == 0, let first = list else { return nil }
    defer { freeifaddrs(list) }
    var counters = NetworkMath.Counters(received: 0, sent: 0)
    var cursor: UnsafeMutablePointer<ifaddrs>? = first
    while let entry = cursor {
      defer { cursor = entry.pointee.ifa_next }
      let flags = Int32(entry.pointee.ifa_flags)
      guard let address = entry.pointee.ifa_addr, address.pointee.sa_family == UInt8(AF_LINK),
        flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0, let data = entry.pointee.ifa_data
      else { continue }
      let name = String(cString: entry.pointee.ifa_name)
      guard name.hasPrefix("en") || name.hasPrefix("pdp_ip") else { continue }
      let stats = data.assumingMemoryBound(to: if_data.self).pointee
      counters.received += UInt64(stats.ifi_ibytes)
      counters.sent += UInt64(stats.ifi_obytes)
    }
    return counters
  }

  /// GPU "Device Utilization %" from the IOAccelerator registry entries, 0...1.
  static func gpuUsage() -> Double? {
    var iterator: io_iterator_t = 0
    guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS
    else { return nil }
    defer { IOObjectRelease(iterator) }
    var best: Double?
    while case let service = IOIteratorNext(iterator), service != 0 {
      defer { IOObjectRelease(service) }
      var properties: Unmanaged<CFMutableDictionary>?
      guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
        let dictionary = properties?.takeRetainedValue() as? [String: Any],
        let stats = dictionary["PerformanceStatistics"] as? [String: Any],
        let percent = (stats["Device Utilization %"] as? NSNumber)?.doubleValue
      else { continue }
      best = max(best ?? 0, percent / 100)
    }
    return best.map { min(1, max(0, $0)) }
  }

  /// The Mac's own battery, if it has one.
  static func battery() -> (percent: Int, charging: Bool)? {
    guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
      let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
    else { return nil }
    for source in sources {
      guard let values = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
        values[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
        let current = values[kIOPSCurrentCapacityKey] as? Int,
        let maximum = values[kIOPSMaxCapacityKey] as? Int,
        let percent = DeviceBattery.percentage(current: current, maximum: maximum)
      else { continue }
      let charging = values[kIOPSIsChargingKey] as? Bool ?? (values[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue)
      return (percent, charging)
    }
    return nil
  }
}

extension ProcessInfo.ThermalState {
  var statsLabel: String {
    switch self {
    case .nominal: "Normal"
    case .fair: "Warm"
    case .serious: "Hot"
    case .critical: "Critical"
    @unknown default: "Unknown"
    }
  }

  /// 0...1 for gauges.
  var statsLevel: Double {
    switch self {
    case .nominal: 0.2
    case .fair: 0.5
    case .serious: 0.8
    case .critical: 1
    @unknown default: 0
    }
  }
}
