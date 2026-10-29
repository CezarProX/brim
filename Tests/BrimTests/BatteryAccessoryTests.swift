import AppKit
import Foundation
import Testing

@testable import Brim

struct BatteryAccessoryTests {
  @Test func appleProductIDsNameTheExactAirPodsModel() {
    let cases: [(Int, AccessoryModel)] = [
      (0x2002, .airPods), (0x200F, .airPods), (0x2013, .airPods3), (0x2019, .airPods4),
      (0x201B, .airPods4), (0x200E, .airPodsPro), (0x2014, .airPodsPro), (0x2024, .airPodsPro),
      (0x2027, .airPodsPro), (0x2028, .airPodsPro), (0x200A, .airPodsMax),
    ]
    for (productID, model) in cases {
      #expect(AccessoryModel.identify(productID: productID, vendorID: 0x004C, name: "Headphones", type: nil) == model)
    }
  }

  @Test func sameProductIDFromAnotherVendorIsNotAirPods() {
    #expect(AccessoryModel.identify(productID: 0x200F, vendorID: 0x05D6, name: "LolliPods", type: "Headphones") == .headphones)
  }

  @Test func renamedOrUnknownIDsFallBackToTheName() {
    #expect(AccessoryModel.identify(productID: nil, vendorID: nil, name: "Alex’s AirPods Max", type: "Headphones") == .airPodsMax)
    #expect(AccessoryModel.identify(productID: 0x9999, vendorID: 0x004C, name: "Powerbeats Pro", type: "Headphones") == .beats(.powerbeatsPro))
    #expect(AccessoryModel.identify(productID: nil, vendorID: nil, name: "Beats Studio Buds +", type: nil) == .beats(.studioBudsPlus))
    #expect(AccessoryModel.identify(productID: nil, vendorID: nil, name: "Beats Studio Buds", type: nil) == .beats(.studioBuds))
    #expect(AccessoryModel.identify(productID: nil, vendorID: nil, name: "Beats Pill", type: nil) == .beats(.pill))
    #expect(AccessoryModel.identify(productID: nil, vendorID: nil, name: "Beats Studio Pro", type: nil) == .beats(.headphones))
  }

  @Test func otherDevicesUseTheirKind() {
    #expect(AccessoryModel.identify(productID: nil, vendorID: nil, name: "Magic Mouse", type: "Mouse") == .magicMouse)
    #expect(AccessoryModel.identify(productID: nil, vendorID: nil, name: "MX Master 3S", type: nil) == .mouse)
    #expect(AccessoryModel.identify(productID: nil, vendorID: nil, name: "Magic Keyboard", type: "Keyboard") == .keyboard)
    #expect(AccessoryModel.identify(productID: nil, vendorID: nil, name: "Magic Trackpad", type: nil) == .trackpad)
    #expect(AccessoryModel.identify(productID: nil, vendorID: nil, name: "DualSense Wireless Controller", type: "Gamepad") == .gameController)
    #expect(AccessoryModel.identify(productID: nil, vendorID: nil, name: "JBL PARTYBOX 310", type: "Hi-Fi Stereo") == .speaker)
    #expect(AccessoryModel.identify(productID: nil, vendorID: nil, name: "Gadget", type: nil) == .other)
  }

  @Test func everyGlyphIsARealSystemSymbol() {
    let models: [AccessoryModel] = [
      .mac, .airPods, .airPods3, .airPods4, .airPodsPro, .airPodsMax, .headphones, .magicMouse, .mouse,
      .keyboard, .trackpad, .gameController, .speaker, .other,
    ] + BeatsFamily.allCases.map { .beats($0) }
    for model in models {
      for part in [nil] + BatteryPart.allCases.map(Optional.some) {
        let glyph = model.glyph(for: part)
        #expect(NSImage(systemSymbolName: glyph, accessibilityDescription: nil) != nil, "\(model) \(String(describing: part)): \(glyph)")
      }
    }
  }

  @Test func airPodsGlyphsMatchTheModelAndPart() {
    #expect(AccessoryModel.airPodsPro.glyph(for: nil) == "airpodspro")
    #expect(AccessoryModel.airPodsPro.glyph(for: .left) == "airpodpro.left")
    #expect(AccessoryModel.airPodsPro.glyph(for: .right) == "airpodpro.right")
    #expect(AccessoryModel.airPodsPro.glyph(for: .case) == "airpodspro.chargingcase.wireless.fill")
    #expect(AccessoryModel.airPods4.glyph(for: .left) == "airpods.gen4.left")
  }

  @Test func probeDecodesTheRealAirPodsRecordAsOneAccessory() {
    let json = #"""
    {"SPBluetoothDataType":[{"device_connected":[{"Alex’s AirPods Pro":{"device_address":"AA:BB","device_batteryLevelCase":"59%","device_batteryLevelLeft":"100%","device_batteryLevelRight":"100%","device_minorType":"Headphones","device_productID":"0x2024","device_vendorID":"0x004C"}}]}]}
    """#
    let devices = BluetoothBatteryProbe.decode(Data(json.utf8))
    #expect(devices.map(\.part) == [.left, .right, .case])
    #expect(Set(devices.map(\.accessoryID)).count == 1)
    #expect(devices.allSatisfy { $0.model == .airPodsPro && $0.accessoryName == "Alex’s AirPods Pro" })
    #expect(devices.map(\.symbol) == ["airpodpro.left", "airpodpro.right", "airpodspro.chargingcase.wireless.fill"])
  }

  @Test func singleBatteryHeadphonesUseTheirMainLevel() {
    let json = #"""
    {"SPBluetoothDataType":[{"device_connected":[{"AirPods Max":{"device_batteryLevelMain":"80%","device_minorType":"Headphones","device_productID":"0x200A","device_vendorID":"0x004C"}}]}]}
    """#
    let devices = BluetoothBatteryProbe.decode(Data(json.utf8))
    #expect(devices.count == 1)
    #expect(devices.first?.part == nil)
    #expect(devices.first?.symbol == "airpodsmax")
    #expect(devices.first?.percent == 80)
  }

  private func battery(_ id: String, _ percent: Int, part: BatteryPart? = nil, accessory: String? = nil,
                       model: AccessoryModel = .airPodsPro, charging: Bool? = nil) -> DeviceBattery {
    DeviceBattery(id: id, name: accessory ?? id, symbol: model.glyph(for: part), percent: percent, charging: charging,
                  accessoryID: accessory ?? id, accessoryName: accessory ?? id, part: part, model: model)
  }

  @Test func equalEarbudsShareOneCellLikeIOS() {
    let pods = [battery("l", 100, part: .left, accessory: "pods"), battery("r", 100, part: .right, accessory: "pods"),
                battery("c", 59, part: .case, accessory: "pods")]
    let accessory = try! #require(BatteryAccessory.group(pods).first)
    #expect(accessory.cells.map(\.percent) == [100, 59])
    #expect(accessory.cells.map(\.glyph) == ["airpodspro", "airpodspro.chargingcase.wireless.fill"])
    #expect(accessory.glyph == "airpodspro")
  }

  @Test func unevenEarbudsStaySeparate() {
    let pods = [battery("l", 90, part: .left, accessory: "pods"), battery("r", 40, part: .right, accessory: "pods")]
    let accessory = try! #require(BatteryAccessory.group(pods).first)
    #expect(accessory.cells.map(\.percent) == [90, 40])
    #expect(accessory.cells.map(\.label) == ["L", "R"])
  }

  @Test func macComesFirstThenAudioThenTheRest() {
    let devices = [battery("mouse", 60, model: .mouse), battery("pods", 80, model: .airPodsMax),
                   battery("mac", 100, model: .mac)]
    #expect(BatteryAccessory.group(devices).map(\.id) == ["mac", "pods", "mouse"])
  }

  @Test func announcementNamesTheAccessoryThatCausedIt() {
    let mac = battery("mac", 100, model: .mac)
    let pods = [battery("l", 80, part: .left, accessory: "pods"), battery("r", 70, part: .right, accessory: "pods")]
    #expect(DeviceBatteryModel.announcement(previous: [mac], next: [mac] + pods) == "pods")
    #expect(DeviceBatteryModel.announcement(previous: [mac] + pods, next: [mac] + pods) == nil)
  }

  @Test func announcesConnectionsChargingAndLowBatteryOnly() {
    let mac = battery("mac", 50, model: .mac, charging: false)
    #expect(!DeviceBatteryModel.shouldAnnounce(previous: [mac], next: [mac]))
    #expect(DeviceBatteryModel.shouldAnnounce(previous: [mac], next: [mac, battery("l", 80, part: .left, accessory: "pods")]))
    #expect(!DeviceBatteryModel.shouldAnnounce(previous: [mac, battery("l", 80, part: .left, accessory: "pods")],
                                               next: [mac, battery("l", 80, part: .left, accessory: "pods"),
                                                      battery("r", 80, part: .right, accessory: "pods")]))
    #expect(DeviceBatteryModel.shouldAnnounce(previous: [mac], next: [battery("mac", 50, model: .mac, charging: true)]))
    #expect(!DeviceBatteryModel.shouldAnnounce(previous: [battery("mac", 50, model: .mac, charging: true)], next: [mac]))
    #expect(DeviceBatteryModel.shouldAnnounce(previous: [battery("mac", 21, model: .mac)], next: [battery("mac", 20, model: .mac)]))
    #expect(DeviceBatteryModel.shouldAnnounce(previous: [battery("mac", 11, model: .mac)], next: [battery("mac", 10, model: .mac)]))
    #expect(!DeviceBatteryModel.shouldAnnounce(previous: [battery("mac", 19, model: .mac)], next: [battery("mac", 18, model: .mac)]))
    #expect(!DeviceBatteryModel.shouldAnnounce(previous: [battery("mac", 21, model: .mac, charging: true)],
                                               next: [battery("mac", 20, model: .mac, charging: true)]))
  }
}

struct BatteryStatusTests {
  private func mac(_ percent: Int, charging: Bool?, onPower: Bool, toEmpty: Int? = nil, toFull: Int? = nil) -> DeviceBattery {
    DeviceBattery(id: "mac", name: "MacBook", symbol: "macbook", percent: percent, charging: charging, model: .mac,
                  onPower: onPower, minutesToEmpty: toEmpty, minutesToFull: toFull)
  }

  @Test func describesTheMacLikeTheBatteryMenu() {
    #expect(BatteryStatus.text(mac(40, charging: true, onPower: true, toFull: 65)) == "Charging · 1 hr 5 min until full")
    #expect(BatteryStatus.text(mac(40, charging: true, onPower: true)) == "Charging")
    #expect(BatteryStatus.text(mac(100, charging: false, onPower: true)) == "Fully charged")
    #expect(BatteryStatus.text(mac(80, charging: false, onPower: true)) == "Charging on hold")
    #expect(BatteryStatus.text(mac(55, charging: false, onPower: false, toEmpty: 200)) == "3 hr 20 min remaining")
    #expect(BatteryStatus.text(mac(55, charging: false, onPower: false, toEmpty: 45)) == "45 min remaining")
    #expect(BatteryStatus.text(mac(55, charging: false, onPower: false)) == "On battery")
  }

  @Test func accessoriesSayConnectedOrCharging() {
    let pods = DeviceBattery(id: "p", name: "AirPods", symbol: "airpodspro", percent: 80, charging: nil, model: .airPodsPro)
    #expect(BatteryStatus.text(pods) == "Connected")
    let charging = DeviceBattery(id: "m", name: "Mouse", symbol: "computermouse.fill", percent: 30, charging: true, model: .mouse)
    #expect(BatteryStatus.text(charging) == "Charging")
  }
}
