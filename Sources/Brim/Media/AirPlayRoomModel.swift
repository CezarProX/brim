import Combine
import Foundation

/// Backs the room picker: the current output ("Living Room"), its volume, and every output to switch to.
/// Honest limit: macOS has no public API to read what an Apple TV plays from its own apps, so this
/// controls the Mac's AirPlay route (switching rooms, volume) and shows the Mac's own Now Playing.
@MainActor
final class AirPlayRoomModel: ObservableObject {
  static let shared = AirPlayRoomModel()
  @Published private(set) var outputs: [AudioDeviceRef] = []
  @Published private(set) var current: AudioDeviceRef?
  @Published private(set) var level: Float?
  /// The last attempt to switch output failed (the device refused to become the default).
  @Published private(set) var switchFailed = false
  private let directory: AudioDeviceListing
  private var timer: Timer?

  private let readLevel: () -> Float?
  private let writeLevel: (Float) -> Bool

  init(
    directory: AudioDeviceListing = CoreAudioDeviceDirectory(),
    readLevel: @escaping () -> Float? = { SystemVolumeControl.read().map { Float($0.level) } },
    writeLevel: @escaping (Float) -> Bool = { SystemVolumeControl.setLevel(Double($0)) }
  ) {
    self.directory = directory
    self.readLevel = readLevel
    self.writeLevel = writeLevel
  }

  var isAirPlay: Bool { current?.isAirPlay == true }
  var roomName: String { current?.name ?? "This Mac" }

  func setActive(_ active: Bool) {
    timer?.invalidate()
    timer = nil
    guard active else { return }
    refresh()
    timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.refresh() }
    }
  }

  func refresh() {
    let all = directory.devices().filter { $0.isOutput && !$0.isAggregate }
    // AirPlay rooms first, then the rest by name.
    outputs = all.sorted { ($0.isAirPlay ? 0 : 1, $0.name) < ($1.isAirPlay ? 0 : 1, $1.name) }
    current = directory.defaultDevice(input: false)
    level = readLevel()
  }

  func select(_ device: AudioDeviceRef) {
    switchFailed = !directory.setDefault(device, input: false)
    refresh()
  }

  /// Sets the volume of the current output directly (the slider); false when the device has no volume control.
  func setLevel(_ value: Float) {
    let clamped = min(1, max(0, value))
    if writeLevel(clamped) { level = clamped }
  }

  var hasAirPlayOutput: Bool { outputs.contains { $0.isAirPlay } }

  func step(up: Bool) {
    guard let level else { return }
    let next = SystemVolumeStepper.next(level: level, up: up)
    if writeLevel(next) { self.level = next }
  }
}
