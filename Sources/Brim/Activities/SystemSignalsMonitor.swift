import AppKit
import CoreAudio
import CoreMediaIO
import IOKit.ps
import IOKit.pwr_mgt

/// Pure rules deciding which power changes deserve a flash, so they can be tested.
enum PowerFlashRules {
  struct Reading: Equatable {
    let percent: Int
    let externalPower: Bool
  }

  enum Flash: Equatable { case charging(Int), unplugged(Int), low(Int), full }

  static let lowThresholds = [20, 10, 5]

  static func flash(previous: Reading?, current: Reading) -> Flash? {
    guard let previous else { return nil }
    // Reaching 100% on the charger, or plugging in at 100%, is "Full Battery" rather than "Charging".
    if current.externalPower, current.percent >= 100, !previous.externalPower || previous.percent < 100 {
      return .full
    }
    if current.externalPower && !previous.externalPower { return .charging(current.percent) }
    if !current.externalPower && previous.externalPower { return .unplugged(current.percent) }
    if !current.externalPower,
      let threshold = lowThresholds.first(where: { current.percent <= $0 && previous.percent > $0 })
    {
      return .low(threshold)
    }
    return nil
  }
}

/// Watches power, camera, microphone and (optionally) downloads, and turns changes into flashes.
/// Everything is read locally from public IOKit, CoreAudio and CoreMediaIO properties.
@MainActor
final class SystemSignalsMonitor: ObservableObject {
  static let shared = SystemSignalsMonitor()
  @Published private(set) var cameraInUse = false
  @Published private(set) var microphoneInUse = false
  @Published private(set) var power: PowerFlashRules.Reading?
  private var timer: Timer?
  private var hotspotPrimed = false
  private let flashes = IslandFlashCenter.shared

  func start() {
    guard timer == nil else { return }
    power = Self.readPower()
    cameraInUse = Self.cameraRunning()
    microphoneInUse = Self.microphoneRunning()
    timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.poll() }
    }
    timer?.tolerance = 0.5
  }

  /// Shows camera or microphone in use without touching hardware, for previews and render tests.
  func preview(camera: Bool, microphone: Bool) {
    cameraInUse = camera
    microphoneInUse = microphone
  }

  func stop() {
    timer?.invalidate()
    timer = nil
  }

  private func poll() {
    let settings = AppSettings.shared
    if let reading = Self.readPower() {
      if let flash = PowerFlashRules.flash(previous: power, current: reading),
        flash == .full ? settings.hudFullBattery : settings.powerFlashesEnabled
      {
        show(flash)
      }
      power = reading
    }
    let camera = Self.cameraRunning()
    if camera != cameraInUse {
      cameraInUse = camera
      // While the quiet indicator is on it says "in use"; only the "off" notice still flashes.
      if settings.privacyFlashesEnabled, !(camera && settings.hudPrivacyIndicator) {
        flashes.show(camera ? "Camera on" : "Camera off", symbol: camera ? "video.fill" : "video.slash.fill",
          tint: camera ? .green : .white)
      }
    }
    let microphone = Self.microphoneRunning()
    if microphone != microphoneInUse {
      microphoneInUse = microphone
      if settings.privacyFlashesEnabled, !(microphone && settings.hudPrivacyIndicator) {
        flashes.show(microphone ? "Mic on" : "Mic off", symbol: microphone ? "mic.fill" : "mic.slash.fill",
          tint: microphone ? .orange : .white)
      }
    }
    pollHotspot(settings)
    if settings.downloadFlashesEnabled { checkDownloads() } else { DownloadProgressModel.shared.stop() }
  }

  /// Personal Hotspot: a notice when the Mac joins a phone's connection, and the indicator while it lasts.
  private func pollHotspot(_ settings: AppSettings) {
    let indicators = SystemStatusIndicators.shared
    guard settings.hudHotspot else {
      indicators.setHotspot(false)
      hotspotPrimed = false
      return
    }
    let tethered = HotspotRules.isTethered(HotspotRules.currentAddresses())
    defer { hotspotPrimed = true }
    guard tethered != indicators.hotspot else { return }
    indicators.setHotspot(tethered)
    if tethered, hotspotPrimed {
      flashes.show(
        "Personal Hotspot", symbol: "personalhotspot", tint: .green, duration: 2.8, detail: "Connected through your phone",
        shortTitle: "Hotspot")
    }
  }

  private func show(_ flash: PowerFlashRules.Flash) {
    switch flash {
    case .full:
      flashes.show(
        "Full Battery", symbol: "battery.100percent.bolt", tint: .green, duration: 5, detail: "Your Mac is fully charged.",
        shortTitle: "Full", autoOpenCard: 4, hero: true)
    case .charging(let percent):
      flashes.show("Charging", symbol: "bolt.fill", tint: .green, value: Double(percent) / 100, duration: 2.6)
    case .unplugged(let percent):
      flashes.show("On battery", symbol: "battery.75percent", tint: .white, value: Double(percent) / 100)
    case .low(let percent):
      flashes.show("Low battery", symbol: "battery.25percent", tint: .red, value: Double(percent) / 100, duration: 4)
    }
  }

  // MARK: Downloads

  /// In-progress browser downloads use these temporary extensions until they finish.
  static let partialExtensions = DownloadFileRules.partialExtensions

  /// Progress, time left and completion live in `DownloadProgressModel`; this keeps it in step with
  /// the setting on the existing 2 s poll.
  private func checkDownloads() { DownloadProgressModel.shared.refresh() }

  // MARK: Readers

  nonisolated static func readPower() -> PowerFlashRules.Reading? {
    guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
      let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
    else { return nil }
    for source in sources {
      guard
        let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue()
          as? [String: Any],
        description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
        let current = description[kIOPSCurrentCapacityKey] as? Int,
        let maximum = description[kIOPSMaxCapacityKey] as? Int, maximum > 0
      else { continue }
      let state = description[kIOPSPowerSourceStateKey] as? String
      return PowerFlashRules.Reading(
        percent: Int((Double(current) / Double(maximum) * 100).rounded()),
        externalPower: state == kIOPSACPowerValue)
    }
    return nil
  }

  nonisolated static func microphoneRunning() -> Bool {
    var device = AudioDeviceID(0)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDefaultInputDevice,
      mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    guard
      AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        == noErr, device != 0
    else { return false }
    address.mSelector = kAudioDevicePropertyDeviceIsRunningSomewhere
    var running: UInt32 = 0
    size = UInt32(MemoryLayout<UInt32>.size)
    guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &running) == noErr else { return false }
    return running != 0
  }

  nonisolated static func cameraRunning() -> Bool {
    var address = CMIOObjectPropertyAddress(
      mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
      mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
      mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
    var size: UInt32 = 0
    guard CMIOObjectGetPropertyDataSize(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, &size) == 0,
      size > 0
    else { return false }
    let count = Int(size) / MemoryLayout<CMIODeviceID>.size
    var devices = [CMIODeviceID](repeating: 0, count: count)
    var used: UInt32 = 0
    guard
      CMIOObjectGetPropertyData(
        CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, size, &used, &devices) == 0
    else { return false }
    address.mSelector = CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere)
    return devices.contains { device in
      var running: UInt32 = 0
      var read: UInt32 = 0
      return CMIOObjectGetPropertyData(
        device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &read, &running) == 0 && running != 0
    }
  }
}

/// Keeps the Mac (and, by default, its display) awake for a while, like Amphetamine or a High Alert card.
@MainActor
final class KeepAwakeModel: ObservableObject {
  static let shared = KeepAwakeModel()
  @Published private(set) var until: Date?
  @Published private(set) var isActive = false
  /// The duration this session was started with (nil = until turned off); drives the highlighted chip.
  @Published private(set) var sessionMinutes: Int?
  /// Whether the display is kept lit too; off lets the screen sleep while the Mac keeps running.
  @Published private(set) var keepsDisplayOn = true
  @Published private(set) var startedAt: Date?
  private var assertion: IOPMAssertionID = 0
  private var expiry: Timer?

  /// The IOKit assertion that implements each mode.
  nonisolated static func assertionType(keepDisplayOn: Bool) -> String {
    keepDisplayOn ? kIOPMAssertionTypePreventUserIdleDisplaySleep : kIOPMAssertionTypePreventUserIdleSystemSleep
  }

  /// `minutes == nil` keeps the Mac awake until turned off.
  func start(minutes: Int?, keepDisplayOn: Bool = true, now: Date = .now) {
    stop(announce: false)
    var id: IOPMAssertionID = 0
    let result = IOPMAssertionCreateWithName(
      Self.assertionType(keepDisplayOn: keepDisplayOn) as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
      "Brim Keep Awake" as CFString, &id)
    guard result == kIOReturnSuccess else {
      IslandFlashCenter.shared.show("Couldn’t keep awake", symbol: "exclamationmark.triangle.fill", tint: .red)
      return
    }
    assertion = id
    isActive = true
    keepsDisplayOn = keepDisplayOn
    sessionMinutes = minutes
    startedAt = now
    until = minutes.map { now.addingTimeInterval(TimeInterval($0 * 60)) }
    if let minutes {
      expiry = Timer.scheduledTimer(withTimeInterval: TimeInterval(minutes * 60), repeats: false) {
        [weak self] _ in Task { @MainActor in self?.stop() }
      }
    }
    IslandFlashCenter.shared.show("Awake", symbol: "cup.and.saucer.fill", tint: .yellow)
  }

  /// Switches between "screen stays on" and "screen may sleep" without changing how long is left.
  func setKeepsDisplayOn(_ on: Bool) {
    guard isActive, on != keepsDisplayOn else { return }
    var id: IOPMAssertionID = 0
    let result = IOPMAssertionCreateWithName(
      Self.assertionType(keepDisplayOn: on) as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
      "Brim Keep Awake" as CFString, &id)
    guard result == kIOReturnSuccess else { return }
    if assertion != 0 { IOPMAssertionRelease(assertion) }
    assertion = id
    keepsDisplayOn = on
  }

  func stop(announce: Bool = true) {
    expiry?.invalidate()
    expiry = nil
    if assertion != 0 { IOPMAssertionRelease(assertion) }
    assertion = 0
    let wasActive = isActive
    isActive = false
    until = nil
    startedAt = nil
    sessionMinutes = nil
    if announce && wasActive {
      IslandFlashCenter.shared.show("Sleep allowed", symbol: "moon.zzz.fill", tint: .white)
    }
  }
}
