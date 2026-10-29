import Foundation
import IOKit
import IOKit.ps

struct DeviceBattery: Identifiable, Equatable, Sendable {
  let id: String
  let name: String
  let symbol: String
  let percent: Int
  let charging: Bool?
  /// Levels of one physical device (AirPods earbuds and case) share an accessory.
  let accessoryID: String
  let accessoryName: String
  let part: BatteryPart?
  let model: AccessoryModel
  /// Mac power source only: on the adapter, and macOS's own time estimates in minutes.
  let onPower: Bool?
  let minutesToEmpty: Int?
  let minutesToFull: Int?
  /// Bluetooth product ID as macOS reports it (e.g. 0x2024), when known; picks system artwork.
  var productID: Int? = nil

  init(id: String, name: String, symbol: String, percent: Int, charging: Bool?,
       accessoryID: String? = nil, accessoryName: String? = nil, part: BatteryPart? = nil,
       model: AccessoryModel = .other, onPower: Bool? = nil, minutesToEmpty: Int? = nil,
       minutesToFull: Int? = nil, productID: Int? = nil) {
    self.id = id
    self.productID = productID
    self.name = name
    self.symbol = symbol
    self.percent = percent
    self.charging = charging
    self.accessoryID = accessoryID ?? id
    self.accessoryName = accessoryName ?? name
    self.part = part
    self.model = model
    self.onPower = onPower
    self.minutesToEmpty = minutesToEmpty.flatMap { $0 > 0 ? $0 : nil }
    self.minutesToFull = minutesToFull.flatMap { $0 > 0 ? $0 : nil }
  }

  static func percentage(current: Int, maximum: Int) -> Int? {
    guard maximum > 0, current >= 0, current <= maximum else { return nil }
    return Int((Double(current) / Double(maximum) * 100).rounded())
  }
}

@MainActor
final class DeviceBatteryModel: ObservableObject {
  static let shared = DeviceBatteryModel()
  @Published private(set) var devices: [DeviceBattery] = []
  @Published private(set) var announcementUntil = Date.distantPast
  /// The accessory the compact island is announcing (AirPods connecting, a charger, a low battery).
  @Published private(set) var announced: BatteryAccessory?
  /// True until the first hardware read finishes, so the Batteries page can say "Looking…" instead of "none".
  @Published private(set) var hasLoaded = false
  @Published private(set) var isRefreshing = false
  @Published private(set) var lastUpdated: Date?
  private var timer: Timer?
  private var refreshing = false
  private var loaded = false

  /// `devices` seeds renders and tests; the app uses `shared`, which reads the real hardware.
  init(devices: [DeviceBattery]? = nil) {
    self.devices = devices ?? []
    hasLoaded = devices != nil
    readsHardware = devices == nil
  }
  private let readsHardware: Bool

  func start() {
    guard timer == nil else { return }
    refresh()
    timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.refresh() }
    }
  }
  func stop() {
    timer?.invalidate()
    timer = nil
  }

  func refresh() {
    guard readsHardware, !refreshing else { return }
    refreshing = true
    isRefreshing = true
    Task {
      let next = await Task.detached(priority: .utility) {
        Self.read() + BluetoothBatteryProbe.read()
      }.value
      if loaded, let id = Self.announcement(previous: devices, next: next) {
        announced = BatteryAccessory.group(next.filter { $0.accessoryID == id }).first
        announcementUntil = .now.addingTimeInterval(6)
      }
      devices = next
      loaded = true
      hasLoaded = true
      lastUpdated = .now
      refreshing = false
      isRefreshing = false
    }
  }

  nonisolated static func shouldAnnounce(previous: [DeviceBattery], next: [DeviceBattery]) -> Bool {
    announcement(previous: previous, next: next) != nil
  }

  /// Like iOS: an accessory connecting, a charger attached, or a battery falling to 20% or 10%.
  /// Returns the accessory to show in the compact island.
  nonisolated static func announcement(previous: [DeviceBattery], next: [DeviceBattery]) -> String? {
    let known = Set(previous.map(\.accessoryID))
    let before = Dictionary(previous.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    for device in next {
      guard known.contains(device.accessoryID) else { return device.accessoryID }
      guard let old = before[device.id] else { continue }
      if device.charging == true && old.charging != true { return device.accessoryID }
      if device.charging != true, [20, 10].contains(where: { old.percent > $0 && device.percent <= $0 }) {
        return device.accessoryID
      }
    }
    return nil
  }

  nonisolated static func read() -> [DeviceBattery] {
    var result: [DeviceBattery] = []
    if let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
      let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
    {
      for source in sources {
        guard
          let values = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue()
            as? [String: Any],
          let current = values[kIOPSCurrentCapacityKey] as? Int,
          let maximum = values[kIOPSMaxCapacityKey] as? Int,
          let percent = DeviceBattery.percentage(current: current, maximum: maximum)
        else { continue }
        let name = String((values[kIOPSNameKey] as? String ?? "Battery").prefix(100))
        let internalBattery = values[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
        result.append(
          DeviceBattery(
            id: "power:\(name)", name: internalBattery ? "Mac" : name,
            symbol: (internalBattery ? AccessoryModel.mac : .other).glyph(for: nil),
            percent: percent, charging: values[kIOPSIsChargingKey] as? Bool,
            accessoryName: internalBattery ? Host.current().localizedName ?? "Mac" : nil,
            model: internalBattery ? .mac : .other,
            onPower: (values[kIOPSPowerSourceStateKey] as? String).map { $0 == kIOPSACPowerValue },
            minutesToEmpty: values[kIOPSTimeToEmptyKey] as? Int,
            minutesToFull: values[kIOPSTimeToFullChargeKey] as? Int))
      }
    }
    var iterator: io_iterator_t = 0
    guard
      IOServiceGetMatchingServices(
        kIOMainPortDefault, IOServiceMatching("AppleDeviceManagementHIDEventService"), &iterator)
        == KERN_SUCCESS
    else { return result }
    defer { IOObjectRelease(iterator) }
    while case let service = IOIteratorNext(iterator), service != 0 {
      defer { IOObjectRelease(service) }
      var properties: Unmanaged<CFMutableDictionary>?
      guard
        IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0)
          == KERN_SUCCESS,
        let values = properties?.takeRetainedValue() as? [String: Any],
        let raw = values["BatteryPercent"] as? Int,
        let percent = DeviceBattery.percentage(current: raw, maximum: 100)
      else { continue }
      let name = String((values["Product"] as? String ?? "Bluetooth device").prefix(100))
      let model = AccessoryModel.identify(
        productID: values["ProductID"] as? Int, vendorID: values["VendorID"] as? Int, name: name, type: nil)
      var registryID: UInt64 = 0
      guard IORegistryEntryGetRegistryEntryID(service, &registryID) == KERN_SUCCESS else {
        continue
      }
      result.append(
        DeviceBattery(
          id: "hid:\(registryID)", name: name, symbol: model.glyph(for: nil), percent: percent,
          charging: values["BatteryIsCharging"] as? Bool, model: model))
      if result.count >= 12 { break }
    }
    return result
  }
}

/// The one-line state under a device, in the words of the macOS battery menu.
enum BatteryStatus {
  static func text(_ device: DeviceBattery) -> String {
    if device.model == .mac, let onPower = device.onPower {
      if device.charging == true {
        return device.minutesToFull.map { "Charging · \(duration($0)) until full" } ?? "Charging"
      }
      if onPower { return device.percent >= 100 ? "Fully charged" : "Charging on hold" }
      return device.minutesToEmpty.map { "\(duration($0)) remaining" } ?? "On battery"
    }
    return device.charging == true ? "Charging" : "Connected"
  }

  static func duration(_ minutes: Int) -> String {
    let hours = minutes / 60, rest = minutes % 60
    if hours == 0 { return "\(rest) min" }
    return rest == 0 ? "\(hours) hr" : "\(hours) hr \(rest) min"
  }
}
