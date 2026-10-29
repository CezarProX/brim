import Foundation
import Testing

@testable import Brim

struct StatsHistoryTests {
  @Test func capsAtCapacityKeepingNewest() {
    var history = StatsHistory()
    for index in 0..<(StatsHistory.capacity + 10) {
      history.record(cpu: Double(index) / 100, memory: 0.5, gpu: nil, down: 0, up: 0)
    }
    #expect(history.cpu.count == StatsHistory.capacity)
    #expect(history.cpu.last == Double(StatsHistory.capacity + 9) / 100)
    #expect(history.gpu.isEmpty)  // unavailable readings are never faked as zero
  }

  @Test func networkScalesToBusiestSampleWithFloor() {
    var history = StatsHistory()
    history.record(cpu: 0, memory: 0, gpu: nil, down: 500_000, up: 500_000)
    history.record(cpu: 0, memory: 0, gpu: nil, down: 250_000, up: 0)
    #expect(history.series(for: .network) == [1, 0.25])
    var idle = StatsHistory()
    idle.record(cpu: 0, memory: 0, gpu: nil, down: 1_000, up: 0)
    #expect(idle.series(for: .network)[0] < 0.02)
  }

  @Test func percentSeriesAreClampedAndCardsWithoutHistoryAreEmpty() {
    var history = StatsHistory()
    history.record(cpu: 1.4, memory: -0.2, gpu: 0.5, down: 0, up: 0)
    #expect(history.series(for: .cpu) == [1])
    #expect(history.series(for: .ram) == [0])
    #expect(history.series(for: .disk).isEmpty)
  }
}

struct BluetoothDevicePrefsTests {
  private let events: [BluetoothHUDRules.Event] = [
    .connected(name: "AirPods", percent: 80), .disconnected(name: "Mouse"), .lowBattery(name: "AirPods", percent: 15),
  ]
  private let ids = ["AirPods": "bluetooth:a", "Mouse": "bluetooth:m"]

  @Test func noPrefsKeepsEverything() {
    #expect(BluetoothDevicePrefs().filter(events, ids: ids) == events)
  }

  @Test func mutingConnectLeavesLowBatteryAlone() {
    let prefs = BluetoothDevicePrefs(mutedConnect: ["bluetooth:a"])
    #expect(prefs.filter(events, ids: ids) == [.disconnected(name: "Mouse"), .lowBattery(name: "AirPods", percent: 15)])
  }

  @Test func mutingLowBatteryLeavesConnectAlone() {
    let prefs = BluetoothDevicePrefs(mutedLowBattery: ["bluetooth:a"])
    #expect(prefs.filter(events, ids: ids).count == 2)
  }

  @Test func unknownDevicesAreKept() {
    let prefs = BluetoothDevicePrefs(mutedConnect: ["bluetooth:a"])
    #expect(prefs.filter([.connected(name: "Ghost", percent: nil)], ids: ids).count == 1)
  }

  @Test func rememberAddsAndRenames() {
    let device = BluetoothHUDRules.Device(id: "bluetooth:a", name: "Alex's AirPods", percent: 50)
    let known = BluetoothDevicePrefs.remember(["bluetooth:a": "AirPods", "bluetooth:z": "Old"], devices: [device])
    #expect(known == ["bluetooth:a": "Alex's AirPods", "bluetooth:z": "Old"])
  }
}

struct DictationCompactLineTests {
  @Test func emptyShowsListening() {
    #expect(DictationCompactLine.tail("  ") == "Listening")
  }

  @Test func shortTextIsUnchanged() {
    #expect(DictationCompactLine.tail("hello there") == "hello there")
  }

  @Test func longTextKeepsNewestWordsWithEllipsis() {
    let line = DictationCompactLine.tail("the quick brown fox jumps over the lazy dog", maxCharacters: 20)
    #expect(line == "…over the lazy dog")
    #expect(line.count <= 21)
  }

  @Test func oversizedSingleWordIsCutFromTheFront() {
    let line = DictationCompactLine.tail("supercalifragilisticexpialidocious", maxCharacters: 10)
    #expect(line.hasPrefix("…"))
    #expect(line.count <= 11)
  }
}

struct SkyRulesTests {
  private let now = Date(timeIntervalSince1970: 1_760_000_000)

  @Test func picksTheEarliestFutureEvent() {
    let rise = now.addingTimeInterval(3600), set = now.addingTimeInterval(7200)
    #expect(SkyRules.nextSunEvent(now: now, sunrises: [now.addingTimeInterval(-100), rise], sunsets: [set])
      == SunEvent(isSunrise: true, date: rise))
    #expect(SkyRules.nextSunEvent(now: now, sunrises: [rise], sunsets: [now.addingTimeInterval(60)])?.isSunrise == false)
    #expect(SkyRules.nextSunEvent(now: now, sunrises: [], sunsets: []) == nil)
  }

  @Test func decodesSunAndAirQuality() throws {
    let sun = #"{"daily":{"sunrise":[1760000100,1760086500],"sunset":[1760040000,null]}}"#
    let decoded = try #require(SkyRules.decodeSun(Data(sun.utf8)))
    #expect(decoded.sunrises.count == 2)
    #expect(decoded.sunsets.count == 1)
    #expect(SkyRules.decodeAQI(Data(#"{"current":{"us_aqi":42.4}}"#.utf8)) == 42)
    #expect(SkyRules.decodeAQI(Data(#"{"current":{"us_aqi":null}}"#.utf8)) == nil)
    #expect(SkyRules.decodeAQI(Data("{}".utf8)) == nil)
  }

  @Test func urlsAreHTTPSAndValidateCoordinates() {
    let sun = SkyRules.sunURL(latitude: 44.43, longitude: 26.1)
    #expect(sun?.scheme == "https")
    #expect(sun?.host == "api.open-meteo.com")
    #expect(SkyRules.airQualityURL(latitude: 44.43, longitude: 26.1)?.host == "air-quality-api.open-meteo.com")
    #expect(SkyRules.sunURL(latitude: 120, longitude: 0) == nil)
  }

  @Test func aqiBandsAndFreshness() {
    #expect(AQICategory.make(30).label == "Good")
    #expect(AQICategory.make(100).label == "Moderate")
    #expect(AQICategory.make(151).label == "Unhealthy")
    #expect(AQICategory.make(400).label == "Hazardous")
    var extras = SkyExtras(); extras.fetchedAt = now.addingTimeInterval(-4 * 3600)
    #expect(!SkyRules.isFresh(extras, now: now))
    extras.fetchedAt = now.addingTimeInterval(-600)
    #expect(SkyRules.isFresh(extras, now: now))
  }
}

struct LowPowerModeControlTests {
  @Test func scriptUsesTheDocumentedPmsetWithAuthorization() {
    #expect(LowPowerModeControl.script(enable: false)
      == "do shell script \"/usr/bin/pmset -a lowpowermode 0\" with administrator privileges")
    #expect(LowPowerModeControl.script(enable: true).contains("lowpowermode 1"))
  }

  @Test func classifiesAppleScriptErrors() {
    #expect(LowPowerModeControl.classify(errorNumber: nil) == .changed)
    #expect(LowPowerModeControl.classify(errorNumber: -128) == .cancelled)
    #expect(LowPowerModeControl.classify(errorNumber: 1) == .failed(code: 1))
  }
}
