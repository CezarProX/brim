import AppKit
import SwiftUI
import Testing

@testable import Brim

/// Renders the open island's pages (Home with and without music, Tray, Widgets, an opened widget,
/// Transform) over a colourful wallpaper so the Dynamic Glass shows, on a notched display and on the
/// island pill. PNGs land in `.renders/redesign-*.png` for side-by-side visual checks.
@MainActor
@Suite(.serialized)
struct IslandRedesignRenderTests {
  enum Style: String, CaseIterable { case notch, pill }

  private let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
  private let canvasWidth: CGFloat = 860

  private func geometry(_ style: Style) -> NotchGeometry {
    style == .notch
      ? NotchGeometry(screenFrame: screen, notchWidth: 184, notchHeight: 32)
      : NotchGeometry.dynamicIsland(screenFrame: screen)
  }

  private func settings() -> AppSettings {
    AppSettings(defaults: UserDefaults(suiteName: "qs-redesign-\(UUID().uuidString)")!)
  }

  struct Setup {
    var nowPlaying: NowPlayingModel?
    var tray: FileTrayStore?
    var traySelection: Set<UUID> = []
    var weather: WeatherStore?
    var widgets: [HomeWidget] = [.clock, .timer, .stats]
    var configure: (NotchPresentation) -> Void = { _ in }
  }

  private func render(_ name: String, style: Style, height: CGFloat, setup: Setup) async throws {
    let presentation = NotchPresentation()
    let geo = geometry(style)
    presentation.geometry = geo
    presentation.isExpanded = true
    setup.configure(presentation)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let player = setup.nowPlaying ?? NowPlayingModel(provider: RedesignPlayer(playing: false, known: false), enabledSources: [])
    let view = NotchShelfView(
      presentation: presentation, store: ShelfStore(directory: directory), nowPlaying: player,
      calls: CallActivityModel(accessibilityTrusted: { false }), recording: ScreenRecordingModel(probe: { nil }),
      timers: NativeTimerModel(),
      tray: setup.tray ?? FileTrayStore(directory: directory.appendingPathComponent("tray")),
      homeWidgets: HomeWidgetStore(widgets: setup.widgets, persist: { _ in }),
      notifications: NotificationHUDModel(settings: settings()), glances: IslandGlanceModel(settings: settings()),
      theme: IslandTheme(surface: .dynamicGlass), weather: setup.weather ?? WeatherStore(settings: settings()),
      playingNext: Self.queue(), initialTraySelection: setup.traySelection)
    let size = CGSize(width: canvasWidth, height: height)
    let wallpaper = Self.wallpaper(size: size)
    let root = ZStack(alignment: .top) {
      Image(nsImage: wallpaper).resizable().frame(width: size.width, height: size.height)
      view.padding(.top, geo.topInset).frame(width: size.width, height: size.height, alignment: .top)
    }
    .environment(\.islandBackdropSnapshot, IslandBackdropSnapshot(image: wallpaper, canvasSize: size))
    .coordinateSpace(name: IslandBackdropSnapshot.coordinateSpace)
    .frame(width: size.width, height: size.height)
    let host = NSHostingView(rootView: root)
    let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    defer { window.close() }
    host.frame = CGRect(origin: .zero, size: size)
    host.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(1600))
    host.layoutSubtreeIfNeeded()
    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    let png = try #require(bitmap.representation(using: .png, properties: [:]))
    try png.write(to: rendersDirectory().appendingPathComponent("redesign-\(name)-\(style.rawValue).png"))
  }

  private func rendersDirectory() throws -> URL {
    let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().appendingPathComponent(".renders")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  // MARK: Pages

  @Test(arguments: Style.allCases) func homeWithMusic(style: Style) async throws {
    let music = NowPlayingModel(provider: RedesignPlayer(playing: true, known: true), enabledSources: [.music])
    await music.refreshNow()
    try await render("home-music", style: style, height: 330, setup: Setup(nowPlaying: music))
  }

  @Test(arguments: Style.allCases) func homeWithoutMusicShowsWidgets(style: Style) async throws {
    try await render("home-widgets", style: style, height: 300, setup: Setup())
  }

  @Test(arguments: Style.allCases) func trayWithFiveFilesOneSelected(style: Style) async throws {
    let fixtures = try TransformFixtures()
    defer { fixtures.cleanup() }
    let tray = try trayStore(fixtures)
    let selected = try #require(tray.items.dropFirst().first?.id)
    try await render("tray-files", style: style, height: 400, setup: Setup(
      tray: tray, traySelection: [selected], configure: { $0.navigate(to: .showing(.tray)) }))
  }

  @Test(arguments: Style.allCases) func trayEmpty(style: Style) async throws {
    try await render("tray-empty", style: style, height: 300, setup: Setup(configure: { $0.navigate(to: .showing(.tray)) }))
  }

  @Test(arguments: Style.allCases) func widgetsPage(style: Style) async throws {
    try await render("widgets", style: style, height: 420, setup: Setup(configure: { $0.navigate(to: .showing(.widgets)) }))
  }

  @Test(arguments: Style.allCases) func weatherWidgetOpened(style: Style) async throws {
    let prefs = settings()
    prefs.weatherEnabled = true
    let weather = WeatherStore(settings: prefs, snapshot: Self.weatherSnapshot())
    try await render("widget-weather", style: style, height: 340, setup: Setup(
      weather: weather, configure: { $0.navigate(to: .opening(.weather)) }))
  }

  @Test(arguments: Style.allCases) func transformPanel(style: Style) async throws {
    let fixtures = try TransformFixtures()
    defer { fixtures.cleanup() }
    let image = try fixtures.image("Tahoe.jpg", width: 1200, height: 800)
    TransformLaunchRequest.shared.operation = .convert
    try await render("transform", style: style, height: 520, setup: Setup(configure: { $0.convertURLs = [image] }))
  }

  @Test func themingSettingsPane() async throws {
    let view = Form { ThemingSettingsSection(theme: IslandTheme(surface: .dynamicGlass, glassLevel: 0.6)) }
      .formStyle(.grouped).frame(width: 600, height: 420, alignment: .topLeading)
      .background(Color(nsColor: .windowBackgroundColor))
    let host = NSHostingView(rootView: view)
    host.frame = CGRect(x: 0, y: 0, width: 600, height: 420)
    host.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(300))
    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    let png = try #require(bitmap.representation(using: .png, properties: [:]))
    try png.write(to: rendersDirectory().appendingPathComponent("redesign-theming-settings.png"))
  }

  // MARK: Fixtures

  private func trayStore(_ fixtures: TransformFixtures) throws -> FileTrayStore {
    let tray = FileTrayStore(directory: fixtures.folder.appendingPathComponent("tray-state"))
    let swans = try fixtures.image("Swans.png", width: 640, height: 400, type: .png, withMetadata: false)
    let orbits = try fixtures.image("Orbits.jpg", width: 600, height: 400)
    let peaks = try fixtures.image("Peaks.png", width: 500, height: 500, type: .png, withMetadata: false)
    let brief = try fixtures.pdf("Brief.pdf", pages: 2, title: "Project brief")
    let notes = fixtures.folder.appendingPathComponent("Notes.txt")
    try "Ship the island redesign.\nMatch the grid spacing.".write(to: notes, atomically: true, encoding: .utf8)
    #expect(tray.add([swans, orbits, peaks, brief, notes]) == 5)
    return tray
  }

  static func queue() -> PlayingNextModel {
    let us = "\u{1F}"
    let rows = [("Blue Hour", "Nova Coast"), ("Low Tide", "Harbor Lights"), ("Paper Planes", "The Quiet Hours")]
    let output = rows.enumerated().map { "\($0.offset + 5)\(us)id\($0.offset)\(us)\($0.element.0)\(us)\($0.element.1)\(us)180" }
      .joined(separator: "\n")
    return PlayingNextModel(read: { _ in output }, perform: { _ in "" }, fetchArtwork: { _ in nil })
  }

  static func weatherSnapshot() -> WeatherSnapshot {
    let base = Date(timeIntervalSince1970: 1_760_000_000)
    let hours = (0..<8).map { index in
      WeatherHour(date: base.addingTimeInterval(Double(index) * 3600), celsius: 21 - Double(index) * 0.6, code: 1, isDay: true)
    }
    return WeatherSnapshot(place: "Bucharest", fetched: base, celsius: 21.4, feelsLikeCelsius: 20, code: 1, isDay: true,
                           highCelsius: 23.6, lowCelsius: 12.1, hours: hours)
  }

  /// A vivid blue night sky with soft clouds and colour blooms.
  static func wallpaper(size: CGSize) -> NSImage {
    NSImage(size: size, flipped: true) { rect in
      NSGradient(colors: [
        NSColor(calibratedRed: 0.09, green: 0.1, blue: 0.86, alpha: 1),
        NSColor(calibratedRed: 0.2, green: 0.16, blue: 0.95, alpha: 1),
        NSColor(calibratedRed: 0.42, green: 0.3, blue: 0.9, alpha: 1),
      ])?.draw(in: rect, angle: 90)
      let blooms: [(CGPoint, CGFloat, NSColor)] = [
        (CGPoint(x: 0.18, y: 0.35), 0.28, NSColor(calibratedRed: 1, green: 0.35, blue: 0.75, alpha: 0.75)),
        (CGPoint(x: 0.82, y: 0.25), 0.25, NSColor(calibratedRed: 0.2, green: 0.9, blue: 1, alpha: 0.7)),
        (CGPoint(x: 0.5, y: 0.1), 0.22, NSColor(calibratedRed: 1, green: 0.75, blue: 0.3, alpha: 0.55)),
      ]
      for (center, radius, color) in blooms {
        let r = radius * rect.width
        let circle = NSBezierPath(ovalIn: CGRect(x: center.x * rect.width - r, y: center.y * rect.height - r, width: 2 * r, height: 2 * r))
        NSGradient(starting: color, ending: color.withAlphaComponent(0))?.draw(in: circle, relativeCenterPosition: .zero)
      }
      NSColor.white.withAlphaComponent(0.85).setFill()
      for index in 0..<60 {
        let x = CGFloat((index * 97) % 1000) / 1000 * rect.width
        let y = CGFloat((index * 61) % 1000) / 1000 * rect.height
        NSBezierPath(ovalIn: CGRect(x: x, y: y, width: 2.4, height: 2.4)).fill()
      }
      for index in 0..<7 {
        let x = CGFloat(index) / 6 * rect.width - 60
        NSColor.white.withAlphaComponent(0.35).setFill()
        NSBezierPath(ovalIn: CGRect(x: x, y: rect.height * 0.62 + CGFloat(index % 3) * 18, width: 220, height: 120)).fill()
      }
      return true
    }
  }
}

private struct RedesignPlayer: NowPlayingProviding {
  var playing: Bool
  var known: Bool
  func connect(_ source: NowPlayingSource) async throws {}
  func snapshot(_ source: NowPlayingSource) async throws -> NowPlayingSnapshot? {
    guard known else { return nil }
    return NowPlayingSnapshot(source: .music, title: "Kill Bill", artist: "SZA", album: "SOS", duration: 153,
                              position: 69, isPlaying: playing)
  }
  func perform(_ command: NowPlayingCommand, expected: NowPlayingSnapshot, token: NowPlayingActionToken) async throws {}
}
