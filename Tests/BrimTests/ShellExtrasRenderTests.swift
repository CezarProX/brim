import AppKit
import SwiftUI
import Testing

@testable import Brim

/// Renders the shell options (clarity, light glass, progressive blur, highlight, favorites, enlarged,
/// low-battery, two glances) to `.renders/extras-*.png`.
@MainActor
@Suite(.serialized)
struct ShellExtrasRenderTests {
  enum Style: String, CaseIterable { case notch, pill }

  private let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)

  private func settings() -> AppSettings {
    AppSettings(defaults: UserDefaults(suiteName: "qs-extras-\(UUID().uuidString)")!)
  }

  private func render(
    _ name: String, style: Style, size: CGSize, expanded: Bool, theme: IslandTheme, tuning: ShellTuning = ShellTuning(),
    glances: IslandGlanceModel? = nil
  ) async throws {
    var geo = style == .notch
      ? NotchGeometry(screenFrame: screen, notchWidth: 184, notchHeight: 32)
      : NotchGeometry.dynamicIsland(screenFrame: screen)
    geo.tuning = tuning
    let presentation = NotchPresentation()
    presentation.geometry = geo
    presentation.isExpanded = expanded
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let view = NotchShelfView(
      presentation: presentation, store: ShelfStore(directory: directory),
      nowPlaying: NowPlayingModel(provider: ExtrasQuietPlayer(), enabledSources: []),
      calls: CallActivityModel(accessibilityTrusted: { false }), recording: ScreenRecordingModel(probe: { nil }),
      timers: NativeTimerModel(), tray: FileTrayStore(directory: directory.appendingPathComponent("tray")),
      homeWidgets: HomeWidgetStore(widgets: [.clock, .timer, .stats], persist: { _ in }),
      notifications: NotificationHUDModel(settings: settings()),
      glances: glances ?? IslandGlanceModel(settings: settings()), theme: theme,
      weather: WeatherStore(settings: settings()))
    let wallpaper = IslandRedesignRenderTests.wallpaper(size: size)
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
    let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().appendingPathComponent(".renders")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try png.write(to: dir.appendingPathComponent("extras-\(name)-\(style.rawValue).png"))
  }

  private let open = CGSize(width: 860, height: 330)

  @Test(arguments: Style.allCases) func clearGlassWithHaloFavoritesAndHighlight(style: Style) async throws {
    let theme = IslandTheme(surface: .dynamicGlass, clarity: 1, highlightHex: "#FF9F0A", windowTintHex: "#30D5C8",
                            progressiveBlur: true)
    try await render("clear-halo", style: style, size: open, expanded: true, theme: theme,
                     tuning: ShellTuning(favorites: [.weather, .notes, .timer, .calendar]))
  }

  @Test(arguments: Style.allCases) func frostedGlass(style: Style) async throws {
    try await render("frosted", style: style, size: open, expanded: true,
                     theme: IslandTheme(surface: .dynamicGlass, clarity: 0))
  }

  @Test(arguments: Style.allCases) func lightGlassInLightMode(style: Style) async throws {
    try await render("light-glass", style: style, size: open, expanded: true,
                     theme: IslandTheme(surface: .dynamicGlass, light: true))
  }

  @Test(arguments: Style.allCases) func lowBatteryIsPlainBlack(style: Style) async throws {
    try await render("low-battery", style: style, size: open, expanded: true,
                     theme: IslandTheme(surface: .liquidGlass, progressiveBlur: true, lowBattery: true))
  }

  @Test(arguments: Style.allCases) func enlargedOpenSize(style: Style) async throws {
    try await render("enlarged", style: style, size: CGSize(width: 960, height: 400), expanded: true,
                     theme: IslandTheme(surface: .dynamicGlass), tuning: ShellTuning(openScale: ShellOpenSize.enlarged.scale))
  }

  @Test func navigationHidden() async throws {
    try await render("no-nav", style: .notch, size: open, expanded: true,
                     theme: IslandTheme(surface: .dynamicGlass), tuning: ShellTuning(showsNavigation: false))
  }

  @Test(arguments: Style.allCases) func twoGlancesPerSideWithNextEvent(style: Style) async throws {
    let meeting = CalendarMeeting(
      id: "m", title: "Design review", startsAt: Date().addingTimeInterval(1800),
      endsAt: Date().addingTimeInterval(5400), calendar: "Work", joinURL: nil)
    CalendarActivityModel.shared.setMeeting(meeting)
    defer { CalendarActivityModel.shared.setMeeting(nil) }
    let prefs = settings()
    prefs.glanceLeft = IslandGlance.clock.rawValue
    prefs.glanceLeftSecond = IslandGlance.event.rawValue
    prefs.glanceRight = IslandGlance.battery.rawValue
    prefs.glanceRightSecond = IslandGlance.cpu.rawValue
    let glances = IslandGlanceModel(settings: prefs, battery: (82, false))
    try await render("glances", style: style, size: CGSize(width: 860, height: 90), expanded: false,
                     theme: IslandTheme(surface: .dynamicGlass), glances: glances)
  }
}

private struct ExtrasQuietPlayer: NowPlayingProviding {
  func connect(_ source: NowPlayingSource) async throws {}
  func snapshot(_ source: NowPlayingSource) async throws -> NowPlayingSnapshot? { nil }
  func perform(_ command: NowPlayingCommand, expected: NowPlayingSnapshot, token: NowPlayingActionToken) async throws {}
}
