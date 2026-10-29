import Foundation

/// A network interface as far as VPN detection cares.
struct NetworkInterfaceInfo: Equatable {
  let name: String
  let hasIPv4: Bool
}

/// Recognizes tunnel interfaces from their BSD names. `utun` also carries system traffic
/// (iCloud Private Relay, Handoff), which only has IPv6 link-local addresses, so a `utun`
/// counts as a VPN only when it has an IPv4 address.
enum VPNInterfaceDetector {
  static let alwaysTunnel = ["ipsec", "ppp", "tun", "tap", "wg"]
  static let needsIPv4 = ["utun"]

  static func isTunnel(_ interface: NetworkInterfaceInfo) -> Bool {
    let name = interface.name.lowercased()
    if alwaysTunnel.contains(where: { name.hasPrefix($0) && name.dropFirst($0.count).allSatisfy(\.isNumber) }) {
      return true
    }
    return interface.hasIPv4 && needsIPv4.contains { name.hasPrefix($0) && name.dropFirst($0.count).allSatisfy(\.isNumber) }
  }

  static func tunnels(in interfaces: [NetworkInterfaceInfo]) -> [String] {
    interfaces.filter(isTunnel).map(\.name).sorted()
  }

  /// Reads up, running interfaces from the kernel.
  static func currentInterfaces() -> [NetworkInterfaceInfo] {
    var head: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&head) == 0, let first = head else { return [] }
    defer { freeifaddrs(head) }
    var ipv4: [String: Bool] = [:]
    for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
      let entry = pointer.pointee
      let flags = Int32(entry.ifa_flags)
      guard flags & IFF_UP != 0, flags & IFF_RUNNING != 0, let address = entry.ifa_addr else { continue }
      let name = String(cString: entry.ifa_name)
      ipv4[name] = (ipv4[name] ?? false) || address.pointee.sa_family == UInt8(AF_INET)
    }
    return ipv4.map { NetworkInterfaceInfo(name: $0.key, hasIPv4: $0.value) }
  }
}

/// Turns consecutive network snapshots into HUD events, so the rules can be tested.
enum NetworkHUDRules {
  struct Snapshot: Equatable {
    var satisfied: Bool
    var usesWiFi: Bool
    var ssid: String?
    var vpnName: String?
  }

  enum Event: Equatable {
    case wifiJoined(ssid: String?)
    case offline
    case vpnConnected(name: String)
    case vpnDisconnected(name: String)
  }

  static func events(previous: Snapshot?, current: Snapshot) -> [Event] {
    guard let previous else { return [] }
    var result: [Event] = []
    let wasOnWiFi = previous.satisfied && previous.usesWiFi
    let isOnWiFi = current.satisfied && current.usesWiFi
    if isOnWiFi, !wasOnWiFi || (current.ssid != nil && current.ssid != previous.ssid) {
      result.append(.wifiJoined(ssid: current.ssid))
    }
    if previous.satisfied, !current.satisfied { result.append(.offline) }
    switch (previous.vpnName, current.vpnName) {
    case (nil, let name?): result.append(.vpnConnected(name: name))
    case (let name?, nil): result.append(.vpnDisconnected(name: name))
    default: break
    }
    return result
  }

  /// "1h 4m", "12m", "45s": compact elapsed time for the VPN card.
  static func shortDuration(_ seconds: TimeInterval) -> String {
    let total = max(0, Int(seconds))
    if total >= 3600 { return "\(total / 3600)h \((total % 3600) / 60)m" }
    if total >= 60 { return "\(total / 60)m" }
    return "\(total)s"
  }
}
