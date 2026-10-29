import Foundation
import Testing

@testable import Brim

@MainActor
@Suite(.serialized)
struct LiveActivityLogicTests {
  // MARK: Focus

  @Test func focusStoreWithAssertionsIsOn() {
    let json = #"{"data":[{"storeAssertionRecords":[{"assertionDetails":{"assertionDetailsModeIdentifier":"com.apple.donotdisturb.mode.default"}}]}]}"#
    let data = Data(json.utf8)
    #expect(FocusAssertions.isActive(data) == true)
    #expect(FocusAssertions.activeName(data) == "Do Not Disturb")
  }

  @Test func focusStoreWithoutAssertionsIsOff() {
    #expect(FocusAssertions.isActive(Data(#"{"data":[{"storeAssertionRecords":[]}]}"#.utf8)) == false)
    #expect(FocusAssertions.isActive(Data(#"{"data":[]}"#.utf8)) == false)
  }

  @Test func unreadableFocusStoreIsUnknownNotOff() {
    #expect(FocusAssertions.isActive(Data("nonsense".utf8)) == nil)
    #expect(FocusAssertions.read(home: URL(fileURLWithPath: "/nonexistent-home")) == nil)
  }

  @Test func focusMonitorFlashesOnlyOnChange() {
    let monitor = FocusHUDMonitor()
    IslandFlashCenter.shared.dismiss()
    monitor.apply(on: false, name: nil)
    #expect(IslandFlashCenter.shared.current == nil)
    monitor.apply(on: true, name: "Work")
    #expect(IslandFlashCenter.shared.current?.title == "Work On")
    #expect(SystemStatusIndicators.shared.focusOn)
    monitor.apply(on: false, name: nil)
    #expect(IslandFlashCenter.shared.current?.title == "Focus Off")
    #expect(!SystemStatusIndicators.shared.focusOn)
    IslandFlashCenter.shared.dismiss()
  }

  // MARK: Hotspot

  @Test func phoneSubnetMeansHotspot() {
    #expect(HotspotRules.isTethered([InterfaceAddress(name: "en0", address: "172.20.10.2")]))
    #expect(!HotspotRules.isTethered([InterfaceAddress(name: "en0", address: "192.168.1.38")]))
    #expect(!HotspotRules.isTethered([InterfaceAddress(name: "lo0", address: "172.20.10.1")]))
    #expect(!HotspotRules.isTethered([]))
  }

  // MARK: Privacy

  @Test func privacyIndicatorCombinesCameraAndMic() {
    #expect(PrivacyIndicator(camera: false, microphone: false) == nil)
    #expect(PrivacyIndicator(camera: true, microphone: false) == .camera)
    #expect(PrivacyIndicator(camera: false, microphone: true) == .microphone)
    #expect(PrivacyIndicator(camera: true, microphone: true) == .both)
    #expect(PrivacyIndicator.microphone.symbol == "mic.fill")
  }

  // MARK: Power

  @Test func reachingFullOnTheChargerIsFull() {
    typealias R = PowerFlashRules.Reading
    #expect(PowerFlashRules.flash(previous: R(percent: 99, externalPower: true), current: R(percent: 100, externalPower: true)) == .full)
    #expect(PowerFlashRules.flash(previous: R(percent: 100, externalPower: false), current: R(percent: 100, externalPower: true)) == .full)
    #expect(PowerFlashRules.flash(previous: R(percent: 100, externalPower: true), current: R(percent: 100, externalPower: true)) == nil)
    #expect(PowerFlashRules.flash(previous: R(percent: 70, externalPower: false), current: R(percent: 70, externalPower: true)) == .charging(70))
  }

  // MARK: Drive, build

  @Test func driveCapacityText() {
    #expect(DriveCapacity.text(available: 654_000_000_000, total: 1_000_000_000_000) == "654 GB available of 1 TB")
    #expect(DriveCapacity.text(available: nil, total: 1_000_000_000_000) == "1 TB")
    #expect(DriveCapacity.text(available: 1, total: nil) == nil)
  }

  @Test func buildPercentIsAnEstimateThatNeverReaches100() {
    #expect(BuildProgress.percent(elapsed: 64, typical: 100) == 64)
    #expect(BuildProgress.percent(elapsed: 500, typical: 100) == 99)
    #expect(BuildProgress.percent(elapsed: 10, typical: nil) == nil)
    #expect(BuildProgress.percent(elapsed: 1, typical: 1) == nil)
  }

  // MARK: Priority and settings

  @Test func quietIndicatorsRankBelowCallsAndRecording() {
    let all = IslandActivities(recording: true, call: true, music: false, additional: [.hotspot, .dnd, .privacy])
    #expect(all.available == [.recording, .call, .privacy, .dnd, .hotspot])
    let quiet = IslandActivities(recording: false, call: false, music: true, additional: [.hotspot, .privacy])
    #expect(quiet.available == [.music, .privacy, .hotspot])
  }

  @Test func newTogglesDefaultOnAndPersist() {
    let settings = AppSettings(defaults: UserDefaults(suiteName: "qs-live-\(UUID().uuidString)")!)
    #expect(settings.hudFullBattery && settings.hudHotspot && settings.hudPrivacyIndicator && settings.hudUpdate && settings.hudFocus)
    settings.hudHotspot = false
    #expect(!settings.hudHotspot)
  }

  @Test func indicatorsPublishOnlyOnChange() {
    let indicators = SystemStatusIndicators()
    indicators.setHotspot(true)
    indicators.setFocus(true, name: "Sleep")
    #expect(indicators.hotspot && indicators.focusOn && indicators.focusName == "Sleep")
    indicators.setFocus(false)
    #expect(!indicators.focusOn && indicators.focusName == nil)
  }
}
