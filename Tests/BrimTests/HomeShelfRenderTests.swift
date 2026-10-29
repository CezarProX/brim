import AppKit
import SwiftUI
import Testing

@testable import Brim

/// Renders the Home widget grid (every widget at every size, the default Home, all-small, two pages,
/// editing with resize handles) to PNGs so the design can be looked at, and checks the cards draw.
@MainActor
@Suite(.serialized)
struct HomeShelfRenderTests {
  private static let output = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().appendingPathComponent(".renders/home-renders", isDirectory: true)

  private func shelf(_ layout: HomeWidgetStore, directory: URL) -> some View {
    IslandWidgetShelf(
      layout: layout, center: ActivityCenter(), store: ShelfStore(directory: directory),
      nowPlaying: NowPlayingModel(enabledSources: []), openTool: { _ in }, showShelf: {}
    )
    .padding(.horizontal, HomeWidgetStore.horizontalPadding / 2).padding(.top, HomeWidgetStore.topPadding)
    .frame(width: layout.shelfWidth, height: layout.shelfHeight, alignment: .top)
    .background(Color.black, in: RoundedRectangle(cornerRadius: 40, style: .continuous))
  }

  private func renderShelf(_ items: [HomeWidgetItem], editing: Bool = false, name: String) async throws -> NSBitmapImageRep {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Brim-HomeShelf-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let layout = HomeWidgetStore(items: items, persist: { _ in }, scrollMode: { .automatic })
    layout.isEditing = editing
    let size = CGSize(width: layout.shelfWidth, height: layout.shelfHeight)
    return try await render(shelf(layout, directory: directory), size: size, name: name)
  }

  private func s(_ widget: HomeWidget) -> HomeWidgetItem { HomeWidgetItem(widget, .small) }
  private func m(_ widget: HomeWidget) -> HomeWidgetItem { HomeWidgetItem(widget, .medium) }

  /// The default Home: Media medium and two smalls fill the four units exactly.
  @Test func defaultHome() async throws {
    let bitmap = try await renderShelf([m(.media), s(.clock), s(.timer)], name: "grid-default")
    #expect(nonBlackPixels(bitmap) > 6_000)
  }

  @Test func idlePlayerAlone() async throws {
    let bitmap = try await renderShelf([m(.media)], name: "idle-player")
    #expect(nonBlackPixels(bitmap) > 3_000)
  }

  @Test func allSmall() async throws {
    let first = try await renderShelf([s(.clock), s(.timer), s(.agenda), s(.captures)], name: "grid-all-small")
    #expect(nonBlackPixels(first) > 6_000)
    _ = try await renderShelf([s(.media), s(.batteries), s(.notes), s(.stats)], name: "grid-all-small-b")
    _ = try await renderShelf([s(.weather), s(.awake), s(.clock)], name: "grid-all-small-c")
  }

  @Test func mediums() async throws {
    _ = try await renderShelf([m(.batteries), m(.timer)], name: "grid-medium-a")
    _ = try await renderShelf([m(.clock), m(.agenda)], name: "grid-medium-b")
    _ = try await renderShelf([m(.notes), m(.stats)], name: "grid-medium-c")
    _ = try await renderShelf([m(.captures), m(.lyrics)], name: "grid-medium-d")
    _ = try await renderShelf([m(.weather), s(.awake)], name: "grid-medium-e")
  }

  /// More than four units page sideways, with dots under the grid; the island keeps the widest page.
  @Test func twoPages() async throws {
    let bitmap = try await renderShelf([m(.media), s(.clock), s(.timer), m(.batteries), s(.agenda)], name: "grid-two-pages")
    #expect(nonBlackPixels(bitmap) > 6_000)
  }

  @Test func editing() async throws {
    let bitmap = try await renderShelf([m(.media), s(.clock), s(.timer)], editing: true, name: "grid-editing")
    #expect(nonBlackPixels(bitmap) > 6_000)
    _ = try await renderShelf([s(.clock), m(.batteries)], editing: true, name: "grid-editing-room")
    _ = try await renderShelf([m(.media), s(.clock), s(.timer), m(.batteries), s(.agenda)], editing: true,
                              name: "grid-editing-two-pages")
  }

  /// Every widget at every size it supports, with fixtures where the live data would be empty.
  @Test func catalog() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Brim-HomeShelf-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = ShelfStore(directory: directory)
    for size in HomeWidgetSize.allCases {
      let widgets = HomeWidget.allCases.filter { $0.supports(size) }
      let perRow = size == .small ? 5 : 3
      let rows = stride(from: 0, to: widgets.count, by: perRow).map { Array(widgets[$0..<min($0 + perRow, widgets.count)]) }
      let sheet = VStack(alignment: .leading, spacing: 18) {
        ForEach(rows.indices, id: \.self) { row in
          HStack(alignment: .top, spacing: HomeWidgetGrid.gap) {
            ForEach(rows[row]) { widget in
              catalogCell(widget, size: size, store: store)
                .frame(width: size.width, height: HomeWidgetGrid.unit)
            }
          }
        }
      }
      .padding(20)
      let width = 40 + HomeWidgetGrid.width(units: perRow * size.units)
      let height = 40 + CGFloat(rows.count) * HomeWidgetGrid.unit + CGFloat(rows.count - 1) * 18
      let bitmap = try await render(sheet, size: CGSize(width: width, height: height), name: "catalog-\(size.rawValue)")
      #expect(nonBlackPixels(bitmap) > 6_000)
    }
  }

  @ViewBuilder private func catalogCell(_ widget: HomeWidget, size: HomeWidgetSize, store: ShelfStore) -> some View {
    let center = ActivityCenter()
    switch widget {
    case .weather:
      if size == .small { HomeWeatherSmallCard(snapshot: Self.weather, unit: .celsius) }
      else { WeatherCard(snapshot: Self.weather, unit: .celsius) }
    case .agenda:
      HomeWidgetCard {
        HomeAgendaWidget(calendar: center.calendar, size: size, open: {}, fixedItems: Self.events)
      }
    case .clock:
      HomeWidgetCard { HomeClockWidget(calendar: center.calendar, size: size, fixedDate: Self.base) }
    case .batteries:
      HomeWidgetCard(padding: size == .small ? 12 : HomeWidgetCard<EmptyView>.padding) {
        HomeBatteriesWidget(model: DeviceBatteryModel(devices: Self.batteries), size: size)
      }
    default:
      HomeWidgetContent(
        widget: widget, size: size, center: center, store: store, nowPlaying: NowPlayingModel(enabledSources: []),
        openTool: { _ in }, showShelf: {})
    }
  }

  private static let base = Date(timeIntervalSince1970: 1_793_000_000)

  private static var weather: WeatherSnapshot {
    let hours = (0..<6).map { WeatherHour(date: base.addingTimeInterval(Double($0) * 3600), celsius: 19 - Double($0), code: 1, isDay: true) }
    return WeatherSnapshot(place: "Bucharest", fetched: base, celsius: 21.4, feelsLikeCelsius: 20, code: 1, isDay: true,
                           highCelsius: 23.6, lowCelsius: 12.1, hours: hours)
  }

  private static var events: [CalendarAgendaItem] {
    [("Design review", 0.5, Color.orange), ("Lunch with Ana", 2.5, Color.green), ("Ship the island build", 5, Color.blue)]
      .map { title, hours, color in
        CalendarAgendaItem(id: title, kind: .event, title: title, start: base.addingTimeInterval(hours * 3600),
                           end: nil, isAllDay: false, color: color, joinURL: nil)
      }
  }

  private static var batteries: [DeviceBattery] {
    [
      DeviceBattery(id: "mac", name: "Mac", symbol: "macbook", percent: 64, charging: true, accessoryName: "MacBook Pro",
                    model: .mac, onPower: true, minutesToFull: 83),
      DeviceBattery(id: "mouse", name: "Magic Mouse", symbol: "magicmouse.fill", percent: 88, charging: false,
                    model: .magicMouse),
      DeviceBattery(id: "kb", name: "Magic Keyboard", symbol: "keyboard.fill", percent: 41, charging: false,
                    model: .keyboard),
    ]
  }

  @Test func batteriesFixtures() async throws {
    func pod(_ part: BatteryPart, _ percent: Int, charging: Bool? = false) -> DeviceBattery {
      DeviceBattery(
        id: "pods-\(part)", name: "AirPods Pro", symbol: AccessoryModel.airPodsPro.glyph(for: part), percent: percent,
        charging: charging, accessoryID: "pods", accessoryName: "AirPods Pro", part: part, model: .airPodsPro)
    }
    let mac = DeviceBattery(
      id: "mac", name: "Mac", symbol: "macbook", percent: 64, charging: true, accessoryName: "MacBook Pro", model: .mac,
      onPower: true, minutesToFull: 83)
    let onBattery = DeviceBattery(
      id: "mac", name: "Mac", symbol: "macbook", percent: 17, charging: false, accessoryName: "MacBook Pro",
      model: .mac, onPower: false, minutesToEmpty: 95)
    let mouse = DeviceBattery(
      id: "mouse", name: "Magic Mouse", symbol: "magicmouse.fill", percent: 88, charging: false, model: .magicMouse)
    let keyboard = DeviceBattery(
      id: "kb", name: "Magic Keyboard", symbol: "keyboard.fill", percent: 41, charging: false, model: .keyboard)
    let pods = [pod(.left, 82), pod(.right, 76), pod(.case, 55, charging: true)]
    let cases: [(String, [DeviceBattery])] = [
      ("mac-airpods", [mac] + pods + [mouse]), ("battery-low", [onBattery, mouse, keyboard]),
      ("desktop", pods + [mouse, keyboard]), ("empty", []),
    ]
    let row = HStack(alignment: .top, spacing: 12) {
      ForEach(cases, id: \.0) { _, devices in
        HomeWidgetCard { HomeBatteriesWidget(model: DeviceBatteryModel(devices: devices)) }
          .frame(width: HomeWidgetSize.medium.width, height: HomeWidgetStore.rowHeight)
      }
    }
    .padding(20)
    let bitmap = try await render(row, size: CGSize(width: 4 * 292 + 3 * 12 + 40, height: 180), name: "batteries")
    let smalls = HStack(alignment: .top, spacing: 12) {
      ForEach(cases, id: \.0) { _, devices in
        HomeWidgetCard(padding: 12) { HomeBatteriesWidget(model: DeviceBatteryModel(devices: devices), size: .small) }
          .frame(width: HomeWidgetSize.small.width, height: HomeWidgetStore.rowHeight)
      }
      HomeWidgetCard(padding: 12) { HomeBatteriesWidget(model: DeviceBatteryModel(devices: [mac]), size: .small) }
        .frame(width: HomeWidgetSize.small.width, height: HomeWidgetStore.rowHeight)
    }
    .padding(20)
    _ = try await render(smalls, size: CGSize(width: 5 * 140 + 4 * 12 + 40, height: 180), name: "batteries-small")
    #expect(nonBlackPixels(bitmap) > 6_000)
  }

  @Test func lyricsWidgetStates() async throws {
    let lrc = "[00:01.00]First light on the water\n[00:05.00]We were drifting slowly home\n[00:09.00]Hold the line until it fades\n[00:13.00]Never let me go"
    let ready = LyricsModel(state: .ready(LRCParser.parse(lrc)))
    let player = NowPlayingModel(enabledSources: [])
    #expect(HomeLyricsWidget.visibleOffsets(index: 1, count: 4) == [0, 1, 2])
    #expect(HomeLyricsWidget.visibleOffsets(index: nil, count: 4) == [0, 1])
    #expect(HomeLyricsWidget.visibleOffsets(index: 3, count: 4) == [2, 3])
    #expect(HomeLyricsWidget.visibleOffsets(index: nil, count: 0).isEmpty)
    let cases: [(LyricsModel, TimeInterval?)] = [
      (ready, 6.0), (LyricsModel(state: .none), nil), (LyricsModel(state: .off), nil),
    ]
    let row = HStack(alignment: .top, spacing: 12) {
      ForEach(Array(cases.enumerated()), id: \.offset) { _, entry in
        HomeWidgetCard { HomeLyricsWidget(model: entry.0, nowPlaying: player, fixedTime: entry.1) }
          .frame(width: HomeWidgetSize.medium.width, height: HomeWidgetStore.rowHeight)
      }
    }
    .padding(20)
    let bitmap = try await render(row, size: CGSize(width: 3 * 292 + 2 * 12 + 40, height: 180), name: "lyrics")
    #expect(nonBlackPixels(bitmap) > 4_000)
    #expect(HomeWidget.allCases.contains(.lyrics) && HomeWidget(rawValue: "lyrics") == .lyrics)
  }

  private func render<V: View>(_ view: V, size: CGSize, name: String) async throws -> NSBitmapImageRep {
    let host = NSHostingView(
      rootView: view.frame(width: size.width, height: size.height, alignment: .topLeading)
        .background(.black).preferredColorScheme(.dark))
    let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    defer { window.close() }
    host.frame = CGRect(origin: .zero, size: size)
    host.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(700))
    host.layoutSubtreeIfNeeded()
    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    try? FileManager.default.createDirectory(at: Self.output, withIntermediateDirectories: true)
    if let png = bitmap.representation(using: .png, properties: [:]) {
      try? png.write(to: Self.output.appendingPathComponent("\(name).png"))
    }
    return bitmap
  }

  private func nonBlackPixels(_ bitmap: NSBitmapImageRep) -> Int {
    var count = 0
    for y in stride(from: 0, to: bitmap.pixelsHigh, by: 2) {
      for x in stride(from: 0, to: bitmap.pixelsWide, by: 2) {
        if let c = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
          c.redComponent + c.greenComponent + c.blueComponent > 0.15
        {
          count += 1
        }
      }
    }
    return count
  }
}
