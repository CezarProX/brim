import AppKit
import SwiftUI
import Testing

@testable import Brim

private struct AppsQuietPlayer: NowPlayingProviding {
  func connect(_ source: NowPlayingSource) async throws {}
  func snapshot(_ source: NowPlayingSource) async throws -> NowPlayingSnapshot? { nil }
  func perform(_ command: NowPlayingCommand, expected: NowPlayingSnapshot, token: NowPlayingActionToken) async throws {}
}

/// Logic behind the Weather, Calendar, Pomodoro and Now Playing apps.
@MainActor
@Suite(.serialized)
struct AppsWeatherCalendarTests {
  private func settings(enabled: Bool = false) -> AppSettings {
    let s = AppSettings(defaults: UserDefaults(suiteName: "qs-apps-\(UUID().uuidString)")!)
    s.weatherEnabled = enabled
    return s
  }

  private let paris = GeocodingResponse.Place(
    id: 1, name: "Paris", latitude: 48.85, longitude: 2.35, country: "France", admin1: "Île-de-France")

  @Test func choosingACityTurnsWeatherOnWithThatPlace() {
    let s = settings()
    let store = WeatherStore(settings: s)
    #expect(store.status == .off)
    store.choose(paris)
    #expect(s.weatherEnabled)
    #expect(s.weatherLocationMode == .custom)
    #expect(s.weatherCityName == "Paris")
    #expect(s.weatherLatitude == 48.85 && s.weatherLongitude == 2.35)
    #expect(store.status == .loading)
    #expect(store.snapshot == nil)
    #expect(store.currentCoordinate?.latitude == 48.85)
  }

  @Test func unitChoiceIsStoredAndResolved() {
    let s = settings(enabled: true)
    let store = WeatherStore(settings: s)
    store.setUnit(.fahrenheit)
    #expect(s.weatherUnit == .fahrenheit)
    #expect(store.unit.format(celsius: 0) == "32°")
  }

  @Test func useMyLocationSwitchesToAutomaticMode() {
    let s = settings()
    let store = WeatherStore(settings: s)
    store.useCurrentLocation()
    #expect(s.weatherEnabled && s.weatherLocationMode == .automatic)
    #expect(store.usesCurrentLocation)
  }

  @Test func dailyOutlookDecodesAndOldCachesStillLoad() throws {
    let json = """
      {"current":{"time":1760000000,"temperature_2m":12.3,"apparent_temperature":10,"weather_code":61,"is_day":1,
       "relative_humidity_2m":56.4,"wind_speed_10m":12.6},
       "hourly":{"time":[1760000000],"temperature_2m":[12.5],"weather_code":[61],"is_day":[1]},
       "daily":{"time":[1759968000,1760054400],"weather_code":[61,3],"precipitation_probability_max":[70,null],
       "temperature_2m_max":[15.2,14],"temperature_2m_min":[8.4,7]}}
      """
    let response = try JSONDecoder().decode(OpenMeteoResponse.self, from: Data(json.utf8))
    let snapshot = try response.snapshot(place: "Berlin", now: Date(timeIntervalSince1970: 1_760_000_000))
    #expect(snapshot.days?.count == 2)
    #expect(snapshot.days?.first?.rainPercent == 70 && snapshot.days?.last?.rainPercent == nil)
    #expect(snapshot.humidityPercent == 56 && snapshot.windKmh == 12.6)
    // A cache written before the outlook existed has no days and must still decode.
    let old = """
      {"place":"X","fetched":0,"celsius":1,"code":0,"isDay":true,"highCelsius":2,"lowCelsius":0,"hours":[]}
      """
    let decoded = try JSONDecoder().decode(WeatherSnapshot.self, from: Data(old.utf8))
    #expect(decoded.days == nil && decoded.humidityPercent == nil)
  }

  @Test func windUsesMilesWhereTemperatureIsFahrenheit() {
    #expect(WeatherNowCard.wind(kmh: 16.09, unit: .fahrenheit) == "10 mph")
    #expect(WeatherNowCard.wind(kmh: 16.09, unit: .celsius) == "16 km/h")
  }

  @Test func nowPlayingTileOpensTheMusicTab() {
    #expect(IslandNavigation.opening(.nowPlaying).page == .music)
    #expect(IslandNavigation.opening(.nowPlaying).openedWidget == nil)
  }

  @Test func theFourAppsExplainThemselves() {
    for tile in [IslandWidgetTile.weather, .calendar, .timer] {
      #expect(tile.subtitle?.isEmpty == false)
    }
  }
}

/// One PNG per app state under `.renders/apps-<app>-<state>.png`.
@MainActor
@Suite(.serialized)
struct AppsWeatherCalendarRenderTests {
  private func settings(enabled: Bool = false) -> AppSettings {
    let s = AppSettings(defaults: UserDefaults(suiteName: "qs-apps-render-\(UUID().uuidString)")!)
    s.weatherEnabled = enabled
    return s
  }

  static func snapshot() -> WeatherSnapshot {
    let base = Date()
    var hours: [WeatherHour] = []
    for index in 0..<8 {
      let step = Double(index)
      let code = index < 3 ? 1 : (index < 6 ? 2 : 61)
      hours.append(WeatherHour(date: base.addingTimeInterval(step * 3600), celsius: 21 - step * 0.7, code: code, isDay: index < 6))
    }
    var days: [WeatherDay] = []
    for (index, code) in [1, 2, 61, 3, 0].enumerated() {
      let step = Double(index)
      let rain = code == 61 ? 70 : (code == 3 ? 30 : 5)
      days.append(
        WeatherDay(
          date: base.addingTimeInterval(step * 86_400), code: code, highCelsius: 23 - step * 1.5,
          lowCelsius: 12 - step, rainPercent: rain))
    }
    return WeatherSnapshot(
      place: "Bucharest", fetched: base.addingTimeInterval(-300), celsius: 21.4, feelsLikeCelsius: 20, code: 1,
      isDay: true, highCelsius: 23.6, lowCelsius: 12.1, hours: hours, days: days, humidityPercent: 54, windKmh: 14)
  }

  private func opened(_ tile: IslandWidgetTile, weather: WeatherStore? = nil) -> some View {
    let weather = weather ?? WeatherStore(settings: AppSettings(defaults: UserDefaults(suiteName: "qs-w-\(UUID())")!))
    return IslandOpenedWidget(
      tile: tile, center: .shared, store: ShelfStore(directory: FileManager.default.temporaryDirectory),
      nowPlaying: NowPlayingModel(provider: AppsQuietPlayer(), enabledSources: []), outputs: .shared,
      outputDrawer: .constant(false), weather: weather, back: {}, open: { _ in })
      .frame(width: IslandPageLayout.widgetsWidth, height: tile.openHeight, alignment: .top)
  }

  private func render<V: View>(_ view: V, name: String, size: CGSize) async throws {
    let framed = view.padding(12).foregroundStyle(.white).background(.black).preferredColorScheme(.dark)
    let host = NSHostingView(rootView: framed)
    let total = CGSize(width: size.width + 24, height: size.height + 24)
    let window = NSWindow(contentRect: CGRect(origin: .zero, size: total), styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    defer { window.close() }
    host.frame = CGRect(origin: .zero, size: total)
    host.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(900))
    host.layoutSubtreeIfNeeded()
    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let dir = root.appendingPathComponent(".renders", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try #require(bitmap.representation(using: .png, properties: [:])).write(to: dir.appendingPathComponent("apps-\(name).png"))
  }

  private func size(_ tile: IslandWidgetTile) -> CGSize { CGSize(width: IslandPageLayout.widgetsWidth, height: tile.openHeight) }

  @Test func weatherFirstRun() async throws {
    try await render(opened(.weather), name: "weather-empty", size: size(.weather))
  }

  @Test func weatherSearching() async throws {
    let found: [GeocodingResponse.Place] = [
      .init(id: 1, name: "Paris", latitude: 0, longitude: 0, country: "France", admin1: "Île-de-France"),
      .init(id: 2, name: "Paris", latitude: 0, longitude: 0, country: "United States", admin1: "Texas"),
      .init(id: 3, name: "Parma", latitude: 0, longitude: 0, country: "Italy", admin1: "Emilia-Romagna"),
    ]
    let view = WeatherSetupView(
      choose: { _ in }, useLocation: {}, search: { _ in found }, query: "Par", results: found)
      .padding(.horizontal, 28).frame(width: IslandPageLayout.widgetsWidth, height: 230, alignment: .top)
    try await render(view, name: "weather-search", size: CGSize(width: IslandPageLayout.widgetsWidth, height: 230))
  }

  @Test func weatherLocationDenied() async throws {
    let view = WeatherSetupView(denied: true, choose: { _ in }, useLocation: {}, search: { _ in [] })
      .padding(.horizontal, 28).frame(width: IslandPageLayout.widgetsWidth, height: 230, alignment: .top)
    try await render(view, name: "weather-denied", size: CGSize(width: IslandPageLayout.widgetsWidth, height: 230))
  }

  @Test func weatherWorking() async throws {
    let s = settings(enabled: true)
    s.weatherUnit = .celsius
    try await render(
      opened(.weather, weather: WeatherStore(settings: s, snapshot: Self.snapshot())), name: "weather-working",
      size: size(.weather))
  }

  @Test func calendarFirstRun() async throws {
    try await render(opened(.calendar), name: "calendar-empty", size: size(.calendar))
  }

  @Test func pomodoroIdle() async throws {
    try await render(opened(.timer), name: "pomodoro-idle", size: size(.timer))
  }

  @Test func pomodoroRunning() async throws {
    let model = FocusTimerModel(flashes: nil)
    model.startPomodoro(focusMinutes: 25, breakMinutes: 5)
    defer { model.stop() }
    let store = FocusSessionStore(defaults: UserDefaults(suiteName: "qs-pomo-\(UUID())")!)
    let view = PomodoroPanelView(model: model, store: store).padding(.horizontal, 28)
      .frame(width: IslandPageLayout.widgetsWidth, height: 180)
    try await render(view, name: "pomodoro-running", size: CGSize(width: IslandPageLayout.widgetsWidth, height: 180))
  }

  @Test func calendarWorking() async throws {
    var cal = Calendar(identifier: .gregorian)
    cal.firstWeekday = 2
    let now = Date()
    func item(_ title: String, _ hour: Double, _ minutes: Double, _ color: Color, join: Bool = false) -> CalendarAgendaItem {
      let start = cal.startOfDay(for: now).addingTimeInterval(hour * 3600)
      return CalendarAgendaItem(
        id: title, kind: .event, title: title, start: start, end: start.addingTimeInterval(minutes * 60), isAllDay: false,
        color: color, joinURL: join ? URL(string: "https://meet.google.com/abc") : nil, location: nil, notes: nil, calendarName: "Work")
    }
    let items = [item("Team standup", 9.5, 15, .blue), item("Launch review", 11, 60, .indigo, join: true), item("Lunch with Maya", 13, 75, .orange)]
    let agenda = CalendarAgendaBuilder.groupExpanded(items, calendar: cal)
    let view = CalendarPageContent(agenda: agenda, calendar: cal, now: now)
      .padding(.horizontal, 28).frame(width: IslandPageLayout.widgetsWidth, height: 240, alignment: .top)
    try await render(view, name: "calendar-working", size: CGSize(width: IslandPageLayout.widgetsWidth, height: 240))
    let empty = CalendarPageContent(agenda: [], calendar: cal, now: now)
      .padding(.horizontal, 28).frame(width: IslandPageLayout.widgetsWidth, height: 240, alignment: .top)
    try await render(empty, name: "calendar-nothing", size: CGSize(width: IslandPageLayout.widgetsWidth, height: 240))
  }
}
