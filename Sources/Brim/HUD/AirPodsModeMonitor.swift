import Foundation

/// Turns consecutive AirPods listening-mode readings into HUDs. The reading itself is best effort:
/// macOS does not publish the mode through any public API, so `modes(in:)` only finds one if the
/// Bluetooth profile carries it (it does not on current macOS). When no mode is ever seen the
/// AirPods connect card with per-bud battery levels is what the user gets.
@MainActor
final class AirPodsModeMonitor {
    static let shared = AirPodsModeMonitor()
    private var previous: [String: AirPodsListeningMode] = [:]

    /// Device name -> listening mode for every connected device that reports one.
    nonisolated static func modes(in profilerJSON: Data) -> [String: AirPodsListeningMode] {
        guard profilerJSON.count <= 1_048_576,
              let root = try? JSONSerialization.jsonObject(with: profilerJSON) as? [String: Any],
              let controllers = root["SPBluetoothDataType"] as? [[String: Any]] else { return [:] }
        var result: [String: AirPodsListeningMode] = [:]
        for controller in controllers {
            for entry in controller["device_connected"] as? [[String: Any]] ?? [] {
                for (name, raw) in entry {
                    if let device = raw as? [String: Any], let mode = AirPodsModeProbe.mode(from: device) { result[name] = mode }
                }
            }
        }
        return result
    }

    /// Devices whose mode changed since the last reading (the first reading never announces).
    func changes(_ current: [String: AirPodsListeningMode]) -> [(name: String, mode: AirPodsListeningMode)] {
        defer { previous = current }
        return current.filter { previous[$0.key] != nil && previous[$0.key] != $0.value }
            .map { ($0.key, $0.value) }.sorted { $0.name < $1.name }
    }

    func ingest(_ profilerJSON: Data) {
        guard AppSettings.shared.hudBluetooth else { return }
        for change in changes(Self.modes(in: profilerJSON)) { present(change.mode, name: change.name) }
    }

    func present(_ mode: AirPodsListeningMode, name: String) {
        IslandFlashCenter.shared.show(
            mode.title, symbol: mode.symbol, tint: mode.tint, duration: 2.6, kind: .bluetooth,
            detail: name, shortTitle: mode.shortTitle)
    }
}
