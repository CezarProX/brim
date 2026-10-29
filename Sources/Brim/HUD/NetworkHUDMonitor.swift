import CoreWLAN
import Network
import SystemConfiguration
import SwiftUI

/// Wi-Fi joined, offline and VPN HUDs from `NWPathMonitor`. Everything stays on device.
@MainActor
final class NetworkHUDMonitor {
  static let shared = NetworkHUDMonitor()
  private var monitor: NWPathMonitor?
  private var previous: NetworkHUDRules.Snapshot?
  private var vpnSince: Date?
  private var offlineWork: Task<Void, Never>?
  private let flashes = IslandFlashCenter.shared
  private var settings: AppSettings { .shared }
  /// Short outages (roaming between access points) shouldn't flash "Offline".
  static let offlineGrace: Duration = .seconds(2.5)

  func refresh() {
    let wanted = settings.hudWiFi || settings.hudOffline || settings.hudVPN
    if wanted, monitor == nil {
      let monitor = NWPathMonitor()
      monitor.pathUpdateHandler = { [weak self] path in
        let satisfied = path.status == .satisfied
        let wifi = path.usesInterfaceType(.wifi)
        Task { @MainActor in self?.pathChanged(satisfied: satisfied, wifi: wifi) }
      }
      monitor.start(queue: DispatchQueue(label: "brim.hud.network"))
      self.monitor = monitor
    } else if !wanted {
      monitor?.cancel()
      monitor = nil
      previous = nil
      offlineWork?.cancel()
    }
  }

  private func pathChanged(satisfied: Bool, wifi: Bool) {
    let snapshot = NetworkHUDRules.Snapshot(
      satisfied: satisfied, usesWiFi: wifi, ssid: wifi ? Self.currentSSID() : nil, vpnName: Self.activeVPNName())
    defer { previous = snapshot }
    for event in NetworkHUDRules.events(previous: previous, current: snapshot) { present(event, snapshot: snapshot) }
    if satisfied { offlineWork?.cancel() }
  }

  private func present(_ event: NetworkHUDRules.Event, snapshot: NetworkHUDRules.Snapshot) {
    switch event {
    case .wifiJoined(let ssid):
      guard settings.hudWiFi else { return }
      flashes.show(
        ssid ?? "Wi-Fi connected", symbol: "wifi", tint: .white, duration: 2.8, kind: .wifi,
        detail: ssid == nil ? nil : "Wi-Fi connected", shortTitle: ssid ?? "Wi-Fi")
    case .offline:
      guard settings.hudOffline else { return }
      offlineWork?.cancel()
      offlineWork = Task { [weak self] in
        try? await Task.sleep(for: Self.offlineGrace)
        guard !Task.isCancelled, let self, self.previous?.satisfied == false else { return }
        self.flashes.show(
          "No Internet", symbol: "wifi.slash", tint: .orange, duration: 3.5, kind: .offline, shortTitle: "Offline")
      }
    case .vpnConnected(let name):
      vpnSince = .now
      guard settings.hudVPN else { return }
      flashes.show(
        name, symbol: "lock.shield.fill", tint: .green, duration: 3.2, kind: .vpn, detail: "VPN connected",
        elapsedSince: vpnSince, shortTitle: "VPN")
    case .vpnDisconnected(let name):
      let elapsed = vpnSince.map { NetworkHUDRules.shortDuration(Date.now.timeIntervalSince($0)) }
      vpnSince = nil
      guard settings.hudVPN else { return }
      flashes.show(
        name, symbol: "lock.open.fill", tint: .white, duration: 2.8, kind: .vpn,
        detail: elapsed.map { "VPN disconnected · \($0)" } ?? "VPN disconnected", shortTitle: "VPN off")
    }
  }

  // MARK: Readers

  /// The SSID when macOS allows reading it without a prompt (it needs Location access on newer
  /// systems); nil otherwise, and the HUD says "Wi-Fi connected" instead.
  nonisolated static func currentSSID() -> String? {
    CWWiFiClient.shared().interface()?.ssid().flatMap { $0.isEmpty ? nil : String($0.prefix(32)) }
  }

  /// A connected VPN's display name: a system network service of VPN type that reports
  /// "connected", else any tunnel interface with an IPv4 address, named "VPN".
  nonisolated static func activeVPNName() -> String? {
    if let service = connectedVPNService() { return service }
    return VPNInterfaceDetector.tunnels(in: VPNInterfaceDetector.currentInterfaces()).isEmpty ? nil : "VPN"
  }

  nonisolated private static func connectedVPNService() -> String? {
    guard let prefs = SCPreferencesCreate(nil, "Brim" as CFString, nil),
      let services = SCNetworkServiceCopyAll(prefs) as? [SCNetworkService]
    else { return nil }
    // The values of kSCNetworkInterfaceTypeVPN / IPSec / L2TP / PPP (VPN is not exported to Swift).
    let vpnTypes: Set<String> = ["VPN", "IPSec", "L2TP", "PPP"]
    for service in services {
      guard let type = SCNetworkServiceGetInterface(service).flatMap({ SCNetworkInterfaceGetInterfaceType($0) as String? }),
        vpnTypes.contains(type), let id = SCNetworkServiceGetServiceID(service),
        let connection = SCNetworkConnectionCreateWithServiceID(nil, id, nil, nil),
        SCNetworkConnectionGetStatus(connection) == .connected
      else { continue }
      return (SCNetworkServiceGetName(service) as String?).map { String($0.prefix(40)) } ?? "VPN"
    }
    return nil
  }
}
