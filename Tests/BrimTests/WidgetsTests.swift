import Foundation
import Testing

@testable import Brim

struct WeatherMappingTests {
  @Test("WMO codes map to conditions, labels and day/night symbols", arguments: [
    (0, "Clear", "sun.max.fill", "moon.stars.fill"),
    (2, "Partly cloudy", "cloud.sun.fill", "cloud.moon.fill"),
    (3, "Overcast", "cloud.fill", "cloud.fill"),
    (45, "Fog", "cloud.fog.fill", "cloud.fog.fill"),
    (63, "Rain", "cloud.rain.fill", "cloud.rain.fill"),
    (65, "Heavy rain", "cloud.heavyrain.fill", "cloud.heavyrain.fill"),
    (73, "Snow", "cloud.snow.fill", "cloud.snow.fill"),
    (81, "Rain showers", "cloud.sun.rain.fill", "cloud.moon.rain.fill"),
    (95, "Thunderstorm", "cloud.bolt.rain.fill", "cloud.bolt.rain.fill"),
    (99, "Thunderstorm, hail", "cloud.bolt.rain.fill", "cloud.bolt.rain.fill"),
  ])
  func mapping(code: Int, label: String, day: String, night: String) {
    let condition = WeatherCondition(code: code)
    #expect(condition.label == label)
    #expect(condition.symbol(isNight: false) == day)
    #expect(condition.symbol(isNight: true) == night)
  }

  @Test func unknownCodesAreHandled() {
    #expect(WeatherCondition(code: 1234) == .unknown)
    #expect(WeatherCondition(code: -1).symbol(isNight: false) == "questionmark.circle")
  }

  @Test func everyKnownCodeHasASymbolAndGradient() {
    for code in [0, 1, 2, 3, 45, 48, 51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 71, 73, 75, 77, 80, 81, 82, 85, 86, 95, 96, 99] {
      let condition = WeatherCondition(code: code)
      #expect(condition != .unknown, "code \(code)")
      #expect(condition.gradient(isNight: true).count == 2)
    }
  }
}

struct WeatherUnitTests {
  @Test func celsiusToFahrenheit() {
    #expect(WeatherUnit.fahrenheit.convert(celsius: 0) == 32)
    #expect(WeatherUnit.fahrenheit.convert(celsius: 100) == 212)
    #expect(WeatherUnit.celsius.convert(celsius: 21.4) == 21.4)
  }

  @Test func automaticFollowsTheRegion() {
    #expect(WeatherUnit.automatic.resolved(locale: Locale(identifier: "en_US")) == .fahrenheit)
    #expect(WeatherUnit.automatic.resolved(locale: Locale(identifier: "en_GB")) == .celsius)
    #expect(WeatherUnit.celsius.resolved(locale: Locale(identifier: "en_US")) == .celsius)
  }

  @Test func formattingRoundsAndAvoidsNegativeZero() {
    #expect(WeatherUnit.celsius.format(celsius: 21.5) == "22°")
    #expect(WeatherUnit.celsius.format(celsius: -0.2) == "0°")
    #expect(WeatherUnit.fahrenheit.format(celsius: 22.2) == "72°")
  }
}

struct OpenMeteoDecodingTests {
  static let fixture = """
    {"latitude":52.52,"longitude":13.41,"utc_offset_seconds":3600,
     "current":{"time":1760000000,"interval":900,"temperature_2m":12.3,"apparent_temperature":10.1,"weather_code":61,"is_day":0},
     "hourly":{"time":[1759990000,1759996800,1760000400,1760004000,1760007600],
       "temperature_2m":[11.0,12.0,12.5,null,13.5],"weather_code":[3,61,61,63,2],"is_day":[0,0,0,0,1]},
     "daily":{"time":[1759959600],"temperature_2m_max":[15.2],"temperature_2m_min":[8.4]}}
    """

  @Test func decodesAndBuildsSnapshot() throws {
    let response = try JSONDecoder().decode(OpenMeteoResponse.self, from: Data(Self.fixture.utf8))
    let now = Date(timeIntervalSince1970: 1_760_000_000)
    let snapshot = try response.snapshot(place: "Berlin", now: now)
    #expect(snapshot.place == "Berlin")
    #expect(snapshot.celsius == 12.3)
    #expect(snapshot.condition == .lightRain)
    #expect(snapshot.isDay == false)
    #expect(snapshot.highCelsius == 15.2 && snapshot.lowCelsius == 8.4)
    // Hours before "now" are dropped, and the null temperature is skipped.
    #expect(snapshot.hours.map(\.celsius) == [12.5, 13.5])
    #expect(snapshot.hours.last?.isDay == true)
  }

  @Test func cacheRoundTrips() throws {
    let response = try JSONDecoder().decode(OpenMeteoResponse.self, from: Data(Self.fixture.utf8))
    let snapshot = try response.snapshot(place: "Berlin", now: Date(timeIntervalSince1970: 1_760_000_000))
    let data = try JSONEncoder().encode(snapshot)
    #expect(try JSONDecoder().decode(WeatherSnapshot.self, from: data) == snapshot)
  }

  @Test func missingDailyDataIsAnError() throws {
    let broken = Self.fixture.replacingOccurrences(of: "[15.2]", with: "[]")
    let response = try JSONDecoder().decode(OpenMeteoResponse.self, from: Data(broken.utf8))
    #expect(throws: WeatherError.missingData) { try response.snapshot(place: "x", now: .now) }
  }

  @Test func requestsAreHTTPSWithoutKeys() throws {
    let url = try #require(WeatherService.forecastURL(latitude: 52.52, longitude: 13.405))
    #expect(url.scheme == "https" && url.host == "api.open-meteo.com")
    #expect(url.query?.contains("timeformat=unixtime") == true)
    #expect(url.query?.contains("latitude=52.5200") == true)
    let search = try #require(WeatherService.geocodingURL(query: "São Paulo"))
    #expect(search.scheme == "https" && search.host == "geocoding-api.open-meteo.com")
    #expect(WeatherService.geocodingURL(query: " a ") == nil)
  }

  @Test func decodesGeocodingResults() throws {
    let json = #"{"results":[{"id":1,"name":"Paris","latitude":48.85,"longitude":2.35,"country":"France","admin1":"Île-de-France"}]}"#
    let places = try JSONDecoder().decode(GeocodingResponse.self, from: Data(json.utf8)).results ?? []
    #expect(places.first?.subtitle == "Île-de-France, France")
    #expect(try JSONDecoder().decode(GeocodingResponse.self, from: Data("{}".utf8)).results == nil)
  }
}

/// A reference wrapper so the mutating policy can be called inside `#expect`.
final class Runner {
  private var policy = StatsAlertPolicy()
  func eval(_ sample: StatsAlertPolicy.Sample, enabled: Set<StatsAlertPolicy.Kind>, now: Date) -> [StatsAlertPolicy.Kind] {
    policy.evaluate(sample, enabled: enabled, now: now)
  }
  func pressure(enabled: Set<StatsAlertPolicy.Kind>, now: Date) -> Bool { policy.memoryPressure(enabled: enabled, now: now) }
}

struct StatsAlertPolicyTests {
  private let t0 = Date(timeIntervalSince1970: 1_000_000)
  private func sample(cpu: Double = 0.1, thermal: ProcessInfo.ThermalState = .nominal, free: Int64 = 100_000_000_000)
    -> StatsAlertPolicy.Sample
  { .init(cpu: cpu, thermal: thermal, diskFree: free, diskTotal: 500_000_000_000) }
  private let all = Set(StatsAlertPolicy.Kind.allCases)

  @Test func cpuMustStayHighForTenSeconds() {
    let policy = Runner()
    #expect(policy.eval(sample(cpu: 0.95), enabled: all, now: t0).isEmpty)
    #expect(policy.eval(sample(cpu: 0.95), enabled: all, now: t0 + 9).isEmpty)
    #expect(policy.eval(sample(cpu: 0.95), enabled: all, now: t0 + 10) == [.highCPU])
  }

  @Test func aDipResetsTheCPUTimer() {
    let policy = Runner()
    _ = policy.eval(sample(cpu: 0.95), enabled: all, now: t0)
    _ = policy.eval(sample(cpu: 0.5), enabled: all, now: t0 + 6)
    #expect(policy.eval(sample(cpu: 0.95), enabled: all, now: t0 + 8).isEmpty)
    #expect(policy.eval(sample(cpu: 0.95), enabled: all, now: t0 + 17).isEmpty)
    #expect(policy.eval(sample(cpu: 0.95), enabled: all, now: t0 + 18) == [.highCPU])
  }

  @Test func alertsAreRateLimited() {
    let policy = Runner()
    _ = policy.eval(sample(cpu: 0.95), enabled: all, now: t0)
    #expect(policy.eval(sample(cpu: 0.95), enabled: all, now: t0 + 10) == [.highCPU])
    #expect(policy.eval(sample(cpu: 0.95), enabled: all, now: t0 + 60).isEmpty)
    #expect(policy.eval(sample(cpu: 0.95), enabled: all, now: t0 + 611) == [.highCPU])
  }

  @Test func disabledKindsNeverFire() {
    let policy = Runner()
    _ = policy.eval(sample(cpu: 0.99, thermal: .critical, free: 1), enabled: [], now: t0)
    #expect(policy.eval(sample(cpu: 0.99, thermal: .critical, free: 1), enabled: [], now: t0 + 30).isEmpty)
    #expect(!policy.pressure(enabled: [], now: t0))
  }

  @Test func thermalFiresOnEnteringSeriousNotWhileStaying() {
    let policy = Runner()
    #expect(policy.eval(sample(thermal: .fair), enabled: all, now: t0).isEmpty)
    #expect(policy.eval(sample(thermal: .serious), enabled: all, now: t0 + 2) == [.highTemperature])
    #expect(policy.eval(sample(thermal: .critical), enabled: all, now: t0 + 4).isEmpty)
  }

  @Test func lowDiskUsesTenGigabytes() {
    let policy = Runner()
    #expect(policy.eval(sample(free: 10_000_000_001), enabled: all, now: t0).isEmpty)
    #expect(policy.eval(sample(free: 9_000_000_000), enabled: all, now: t0 + 2) == [.lowDisk])
    let unknown = Runner()
    let noDisk = StatsAlertPolicy.Sample(cpu: 0, thermal: .nominal, diskFree: 0, diskTotal: 0)
    #expect(unknown.eval(noDisk, enabled: all, now: t0).isEmpty)
  }

  @Test func memoryPressureHonorsCooldown() {
    let policy = Runner()
    #expect(policy.pressure(enabled: all, now: t0))
    #expect(!policy.pressure(enabled: all, now: t0 + 30))
    #expect(policy.pressure(enabled: all, now: t0 + 700))
  }
}

struct StatsReadingTests {
  @Test func networkRatesHandleCounterWrap() {
    let a = NetworkMath.Counters(received: 4_294_967_000, sent: 100)
    let b = NetworkMath.Counters(received: 1_000, sent: 2_100)
    let rates = NetworkMath.rates(from: a, to: b, seconds: 2)
    #expect(rates.down == 648)  // (4_294_967_296 - 4_294_967_000 + 1_000) / 2
    #expect(rates.up == 1000)
    #expect(NetworkMath.rates(from: a, to: b, seconds: 0).down == 0)
  }

  @Test func networkFormatting() {
    #expect(NetworkMath.format(0) == "0 B/s")
    #expect(NetworkMath.format(340_000) == "340 KB/s")
    #expect(NetworkMath.format(1_250_000) == "1.2 MB/s")
  }

  @Test func cardsReadFromTheInput() {
    var input = StatsCardReading.Input()
    input.cpu = 0.424
    input.batteryPercent = 15
    input.thermal = .serious
    #expect(StatsCardReading.make(.cpu, input).center == "42%")
    #expect(StatsCardReading.make(.battery, input).tint == .red)
    #expect(StatsCardReading.make(.thermal, input).center == "Hot")
    #expect(StatsCardReading.make(.gpu, input).center == "–")
    input.batteryPercent = nil
    #expect(StatsCardReading.make(.battery, input).detail == "No battery")
  }
}

struct GlanceFormatTests {
  @Test func clockDropsTheDayPeriod() {
    let date = Date(timeIntervalSince1970: 1_760_000_000)  // 2025-10-09 08:53:20 UTC
    let utc = TimeZone(identifier: "UTC")!
    #expect(GlanceFormat.clock(date, locale: Locale(identifier: "en_US"), timeZone: utc) == "8:53")
    #expect(GlanceFormat.clock(date, locale: Locale(identifier: "de_DE"), timeZone: utc) == "08:53")
  }

  @Test func batteryText() {
    #expect(GlanceFormat.battery(percent: 64) == "64%")
    #expect(GlanceFormat.battery(percent: 140) == "100%")
    #expect(GlanceFormat.batterySymbol(percent: 5, charging: false) == "battery.0percent")
    #expect(GlanceFormat.batterySymbol(percent: 70, charging: false) == "battery.75percent")
    #expect(GlanceFormat.batterySymbol(percent: 70, charging: true) == "battery.100percent.bolt")
  }

  @Test func timerText() {
    #expect(GlanceFormat.timer(0) == "0:00")
    #expect(GlanceFormat.timer(59.2) == "1:00")
    #expect(GlanceFormat.timer(25 * 60) == "25:00")
    #expect(GlanceFormat.timer(3725) == "1:02:05")
    #expect(GlanceFormat.timer(-5) == "0:00")
  }

  @Test func cpuText() {
    #expect(GlanceFormat.cpu(0.426) == "43%")
    #expect(GlanceFormat.cpu(3) == "100%")
  }

  @Test @MainActor func glancesPersistAndGateOnContent() {
    let defaults = UserDefaults(suiteName: "glance-test-\(UUID().uuidString)")!
    let model = IslandGlanceModel(settings: AppSettings(defaults: defaults))
    #expect(model.left == .none && !model.hasContent(.left))
    model.set(.clock, for: .left)
    model.set(.timer, for: .right)
    #expect(model.hasContent(.left))
    #expect(model.reservedWidth(.left) == IslandGlanceModel.glanceWidth)
    #expect(AppSettings(defaults: defaults).glanceLeft == "clock")
    #expect(model.hasContent(.right) == FocusTimerModel.shared.isActive)
  }
}

@MainActor
struct HomeWidgetPagingTests {
  @Test func pagesOfFourUnitsUpToTwo() {
    let store = HomeWidgetStore(widgets: [.batteries], persist: { _ in }, scrollMode: { .automatic })
    for widget in [HomeWidget.captures, .timer, .stats, .weather, .notes, .clock] { store.toggle(widget) }
    // M S S | M M — then both pages are full, so Notes and Clock are refused.
    #expect(store.widgets == [.batteries, .captures, .timer, .stats, .weather])
    #expect(store.pages.map { HomeWidgetGrid.units($0) } == [4, 4])
    #expect(!store.pagesVertically)
    #expect(store.shelfWidth == HomeWidgetGrid.width(units: 4) + HomeWidgetStore.horizontalPadding)
  }

  @Test func removingTheLastPageClampsThePage() {
    let store = HomeWidgetStore(widgets: [.media, .captures, .timer, .stats], persist: { _ in }, scrollMode: { .twoRows })
    // M M | S M (Captures is medium by default): emptying page two moves back to page one.
    store.page = 1
    store.toggle(.stats)
    #expect(store.page == 1)
    store.toggle(.timer)
    #expect(store.page == 0)
    #expect(store.pagesVertically)
  }
}

@MainActor
struct PomodoroAutoStartTests {
  @Test func waitsForPlayWhenAutoStartIsOff() {
    let model = FocusTimerModel(autoStartNext: { false })
    let start = Date(timeIntervalSince1970: 5_000)
    model.startPomodoro(focusMinutes: 25, breakMinutes: 5, now: start)
    model.tick(now: start + 25 * 60)
    #expect(model.phase == .rest && model.completedSessions == 1)
    #expect(model.isPaused)
    #expect(model.remaining(at: start + 99_999) == 5 * 60)
    model.resume(now: start + 30 * 60)
    #expect(!model.isPaused)
    model.stop()
  }
}
