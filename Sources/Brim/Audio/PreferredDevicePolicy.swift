import CoreAudio
import Foundation

/// When a favourite audio device shows up, make it the default. Pure, so the rules are testable.
enum PreferredDevicePolicy {
  /// - Parameters:
  ///   - preferred: device uids, highest priority first.
  ///   - available: every device now present.
  ///   - previous: uids that were present at the last evaluation (nothing is "new" on the first scan).
  ///   - currentUID: the current default for this direction.
  /// - Returns: the device to switch to, or nil to leave the route alone.
  static func target(
    preferred: [String], available: [AudioDeviceRef], previous: Set<String>, currentUID: String?, input: Bool
  ) -> AudioDeviceRef? {
    let usable = available.filter { input ? $0.isInput : $0.isOutput }
    let rank = Dictionary(preferred.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
    let arrived = usable.filter { rank[$0.uid] != nil && !previous.contains($0.uid) }
    guard let best = arrived.min(by: { rank[$0.uid]! < rank[$1.uid]! }) else { return nil }
    if best.uid == currentUID { return nil }
    // Never demote: if the user already sits on a higher-priority favourite, stay there.
    if let current = currentUID, let currentRank = rank[current], currentRank < rank[best.uid]! { return nil }
    return best
  }
}

/// Watches the device list and applies `PreferredDevicePolicy`.
@MainActor
final class PreferredDeviceMonitor {
  static let shared = PreferredDeviceMonitor()
  private let directory: AudioDeviceListing
  private let settings: AppSettings
  private var previous: Set<String>?
  private var listener: AudioObjectPropertyListenerBlock?
  private var address = CoreAudioProperty.address(kAudioHardwarePropertyDevices)

  init(directory: AudioDeviceListing = CoreAudioDeviceDirectory(), settings: AppSettings = .shared) {
    self.directory = directory
    self.settings = settings
  }

  func start() {
    guard listener == nil else { return }
    let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
      Task { @MainActor in self?.evaluate() }
    }
    listener = block
    AudioObjectAddPropertyListenerBlock(CoreAudioProperty.system, &address, .main, block)
    evaluate()
  }

  func stop() {
    if let listener { AudioObjectRemovePropertyListenerBlock(CoreAudioProperty.system, &address, .main, listener) }
    listener = nil
    previous = nil
  }

  /// Exposed for tests and for a "re-check now" button.
  func evaluate() {
    let available = directory.devices()
    let now = Set(available.map(\.uid))
    defer { previous = now }
    guard settings.preferredDevicesEnabled, let seen = previous else { return }
    for input in [false, true] {
      let list = input ? settings.preferredInputUIDs : settings.preferredOutputUIDs
      guard !list.isEmpty else { continue }
      let current = directory.defaultDevice(input: input)?.uid
      if let target = PreferredDevicePolicy.target(
        preferred: list, available: available, previous: seen, currentUID: current, input: input) {
        directory.setDefault(target, input: input)
      }
    }
  }
}
