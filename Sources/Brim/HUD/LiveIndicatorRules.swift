import Foundation

/// Reads Focus (Do Not Disturb) state. macOS has no public push API, so this parses the
/// assertion store that `donotdisturbd` keeps; the file sits behind Full Disk Access, so a
/// nil answer means "unknown", never "off".
enum FocusAssertions {
  /// True when at least one Focus assertion is active, false when the store is readable and
  /// empty, nil when the data is not the shape we know.
  static func isActive(_ data: Data) -> Bool? {
    guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
      let entries = root["data"] as? [[String: Any]]
    else { return nil }
    return entries.contains { !(($0["storeAssertionRecords"] as? [Any]) ?? []).isEmpty }
  }

  /// The active Focus' name when it is one of the built-ins.
  static func activeName(_ data: Data) -> String? {
    guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
      let entries = root["data"] as? [[String: Any]]
    else { return nil }
    let names = [
      "com.apple.donotdisturb.mode.default": "Do Not Disturb", "com.apple.sleep.sleep-mode": "Sleep",
      "com.apple.focus.work": "Work", "com.apple.focus.personal-time": "Personal",
      "com.apple.focus.driving": "Driving", "com.apple.focus.reading": "Reading",
      "com.apple.focus.gaming": "Gaming", "com.apple.focus.fitness": "Fitness",
      "com.apple.focus.mindfulness": "Mindfulness",
    ]
    for entry in entries {
      for record in (entry["storeAssertionRecords"] as? [[String: Any]]) ?? [] {
        let details = record["assertionDetails"] as? [String: Any]
        if let id = details?["assertionDetailsModeIdentifier"] as? String { return names[id] }
      }
    }
    return nil
  }

  static let storePath = "Library/DoNotDisturb/DB/Assertions.json"

  /// Reads the store from `home`; nil when macOS (privacy protection) refuses or it is absent.
  static func read(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> (active: Bool, name: String?)? {
    guard let data = try? Data(contentsOf: home.appendingPathComponent(storePath)),
      let active = isActive(data)
    else { return nil }
    return (active, active ? activeName(data) : nil)
  }
}

/// An IPv4 address on a network interface, as far as tethering detection cares.
struct InterfaceAddress: Equatable {
  let name: String
  let address: String
}

/// Personal Hotspot detection. An iPhone (or iPad) sharing its connection always hands out
/// addresses from 172.20.10.0/28 over Wi-Fi, USB and Bluetooth, so an interface holding one
/// means this Mac is online through a phone.
enum HotspotRules {
  static func isTethered(_ addresses: [InterfaceAddress]) -> Bool {
    addresses.contains { $0.address.hasPrefix("172.20.10.") && !$0.name.hasPrefix("lo") }
  }

  /// Up, running IPv4 addresses from the kernel.
  static func currentAddresses() -> [InterfaceAddress] {
    var head: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&head) == 0, let first = head else { return [] }
    defer { freeifaddrs(head) }
    var result: [InterfaceAddress] = []
    for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
      let entry = pointer.pointee
      let flags = Int32(entry.ifa_flags)
      guard flags & IFF_UP != 0, flags & IFF_RUNNING != 0, let address = entry.ifa_addr,
        address.pointee.sa_family == UInt8(AF_INET)
      else { continue }
      var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
      guard getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0
      else { continue }
      result.append(InterfaceAddress(name: String(cString: entry.ifa_name), address: String(cString: host)))
    }
    return result
  }
}

/// What the always-on indicators in the closed island say. Camera and microphone come from
/// `SystemSignalsMonitor`; Focus and the hotspot are set by their monitors.
enum PrivacyIndicator: Equatable {
  case camera, microphone, both

  init?(camera: Bool, microphone: Bool) {
    switch (camera, microphone) {
    case (true, true): self = .both
    case (true, false): self = .camera
    case (false, true): self = .microphone
    case (false, false): return nil
    }
  }

  var symbol: String { self == .microphone ? "mic.fill" : "video.fill" }
  var title: String {
    switch self {
    case .camera: "Camera in use"
    case .microphone: "Microphone in use"
    case .both: "Camera and microphone in use"
    }
  }
}

/// Drive card text: "654 GB available of 1 TB".
enum DriveCapacity {
  static func text(available: Int?, total: Int?) -> String? {
    guard let total, total > 0 else { return nil }
    let totalText = ByteCountFormatter.string(fromByteCount: Int64(total), countStyle: .file)
    guard let available, available >= 0 else { return totalText }
    return "\(ByteCountFormatter.string(fromByteCount: Int64(available), countStyle: .file)) available of \(totalText)"
  }
}

/// A build has no progress signal in DerivedData, so the percentage compares the time spent so
/// far with how long the previous build of the same project took. Never reaches 100 before the
/// build actually ends.
enum BuildProgress {
  static func percent(elapsed: TimeInterval, typical: TimeInterval?) -> Int? {
    guard let typical, typical >= 3, elapsed >= 0 else { return nil }
    return min(99, Int((elapsed / typical * 100).rounded(.down)))
  }
}
