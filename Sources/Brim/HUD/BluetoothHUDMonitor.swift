import CoreAudio
import Foundation
import SwiftUI

/// Connect / disconnect / low-battery events from consecutive Bluetooth device snapshots.
enum BluetoothHUDRules {
  struct Device: Equatable {
    let id: String
    let name: String
    /// Lowest battery across the device's parts, if it reports any.
    let percent: Int?
    /// Per-bud and case levels when the device is AirPods.
    var airPods: AirPodsBatteries? = nil
  }

  enum Event: Equatable {
    case connected(name: String, percent: Int?)
    case disconnected(name: String)
    case lowBattery(name: String, percent: Int)
  }

  static let lowThreshold = 20

  static func events(previous: [Device]?, current: [Device]) -> [Event] {
    guard let previous else { return [] }
    let old = Dictionary(previous.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    let new = Dictionary(current.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    var events: [Event] = []
    for device in current.sorted(by: { $0.name < $1.name }) {
      guard let before = old[device.id] else {
        events.append(.connected(name: device.name, percent: device.percent))
        continue
      }
      if let now = device.percent, now <= lowThreshold, (before.percent ?? 100) > lowThreshold {
        events.append(.lowBattery(name: device.name, percent: now))
      }
    }
    for device in previous.sorted(by: { $0.name < $1.name }) where new[device.id] == nil {
      events.append(.disconnected(name: device.name))
    }
    return events
  }

  /// Collapses the probe's per-part readings (left, right, case) into one entry per accessory.
  static func devices(from batteries: [DeviceBattery]) -> [Device] {
    var order: [String] = []
    var grouped: [String: (name: String, percents: [Int])] = [:]
    for battery in batteries {
      let id = battery.accessoryID
      guard id.hasPrefix("bluetooth:") else { continue }
      if grouped[id] == nil { order.append(id) }
      var entry = grouped[id] ?? (battery.accessoryName, [])
      // The case is charged separately from the earbuds; only low buds should alert.
      if battery.part != .case { entry.percents.append(battery.percent) }
      grouped[id] = entry
    }
    return order.compactMap { id in
      grouped[id].map {
        Device(id: id, name: $0.name, percent: $0.percents.min(), airPods: AirPodsBatteries.from(batteries, accessoryID: id))
      }
    }
  }
}

/// Bluetooth connect/disconnect and low-battery HUDs. Reads `system_profiler` through the
/// existing `BluetoothBatteryProbe`, so no Bluetooth permission prompt is needed; the cost is
/// that only devices reporting a battery level are seen. Headphones show up as a Core Audio device
/// the moment they connect, so a change in the audio device list reads again at once (and a few
/// times more while AirPods start reporting their batteries) instead of waiting for the next poll.
@MainActor
final class BluetoothHUDMonitor {
  static let shared = BluetoothHUDMonitor()
  static let pollInterval: TimeInterval = 20
  private var timer: Timer?
  private var previous: [BluetoothHUDRules.Device]?
  private var polling = false
  private var audioListener: AudioObjectPropertyListenerBlock?
  private var burst: Task<Void, Never>?
  /// Seconds after an audio device change to read again; AirPods report batteries a moment after connecting.
  static let burstDelays: [TimeInterval] = [1, 3, 6, 10]

  func refresh() {
    if AppSettings.shared.hudBluetooth, timer == nil {
      listenForAudioDevices()
      poll()
      timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
        Task { @MainActor in self?.poll() }
      }
      timer?.tolerance = 3
    } else if !AppSettings.shared.hudBluetooth {
      timer?.invalidate()
      timer = nil
      previous = nil
      stopListeningForAudioDevices()
    }
  }

  private static var devicesAddress = AudioObjectPropertyAddress(
    mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal,
    mElement: kAudioObjectPropertyElementMain)

  private func listenForAudioDevices() {
    guard audioListener == nil else { return }
    let block: AudioObjectPropertyListenerBlock = { _, _ in
      Task { @MainActor in BluetoothHUDMonitor.shared.audioDevicesChanged() }
    }
    var address = Self.devicesAddress
    let status = AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, block)
    if status == noErr { audioListener = block }
  }

  private func stopListeningForAudioDevices() {
    burst?.cancel()
    guard let block = audioListener else { return }
    var address = Self.devicesAddress
    AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, block)
    audioListener = nil
  }

  private func audioDevicesChanged() {
    guard AppSettings.shared.hudBluetooth else { return }
    burst?.cancel()
    burst = Task { @MainActor [weak self] in
      var waited: TimeInterval = 0
      for delay in Self.burstDelays {
        try? await Task.sleep(for: .seconds(delay - waited))
        waited = delay
        guard !Task.isCancelled else { return }
        self?.poll()
      }
    }
  }

  private func poll() {
    guard !polling else { return }
    polling = true
    Task.detached(priority: .utility) {
      let data = BluetoothBatteryProbe.boundedOutput(
        executable: "/usr/sbin/system_profiler",
        arguments: ["SPBluetoothDataType", "-json", "-detailLevel", "basic", "-timeout", "4"], timeout: 5)
      let devices = BluetoothHUDRules.devices(from: data.map(BluetoothBatteryProbe.decode) ?? [])
      await MainActor.run { [weak self] in
        self?.polling = false
        self?.apply(devices)
        if let data { AirPodsModeMonitor.shared.ingest(data) }
      }
    }
  }

  private func apply(_ devices: [BluetoothHUDRules.Device]) {
    guard AppSettings.shared.hudBluetooth else { return }
    let settings = AppSettings.shared
    let events = BluetoothHUDRules.events(previous: previous, current: devices)
    var ids: [String: String] = [:]
    for device in (previous ?? []) + devices { ids[device.name] = device.id }
    let prefs = BluetoothDevicePrefs(
      mutedConnect: settings.bluetoothMutedConnect, mutedLowBattery: settings.bluetoothMutedLowBattery)
    let known = BluetoothDevicePrefs.remember(settings.bluetoothKnownDevices, devices: devices)
    if known != settings.bluetoothKnownDevices { settings.bluetoothKnownDevices = known }
    previous = devices
    for event in prefs.filter(events, ids: ids) { present(event, devices: devices) }
  }

  private func present(_ event: BluetoothHUDRules.Event, devices: [BluetoothHUDRules.Device]) {
    let flashes = IslandFlashCenter.shared
    switch event {
    case .connected(let name, _) where AppSettings.shared.hudAirPodsCard
      && devices.first(where: { $0.name == name })?.airPods?.hasAny == true:
      if let pods = devices.first(where: { $0.name == name })?.airPods {
        AirPodsConnectCard.present(pods, name: name, center: flashes)
      }
    case .connected(let name, let percent):
      flashes.show(
        name, symbol: "headphones", tint: .blue, value: percent.map { Double($0) / 100 }, duration: 3.2,
        kind: .bluetooth, detail: "Connected", shortTitle: percent == nil ? "Connected" : nil)
    case .disconnected(let name):
      flashes.show(
        name, symbol: "headphones", tint: .white, duration: 2.6, kind: .bluetooth, detail: "Disconnected",
        shortTitle: "Disconnected")
    case .lowBattery(let name, let percent):
      flashes.show(
        name, symbol: "battery.25percent", tint: .red, value: Double(percent) / 100, duration: 4,
        kind: .bluetooth, detail: "Low battery")
    }
  }
}
