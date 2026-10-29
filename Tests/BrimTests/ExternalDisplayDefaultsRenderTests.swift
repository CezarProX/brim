import AppKit
import SwiftUI
import Testing

@testable import Brim

/// With the default display settings a notchless external monitor gets the floating Dynamic
/// Island pill. Renders the closed and open island on a 1920×1080 and a 3440×1440 display (idle,
/// music, HUD) into `.renders/external-*.png`.
@MainActor
@Suite(.serialized)
struct ExternalDisplayDefaultsRenderTests {
  enum Display: String, CaseIterable {
    case fhd = "1920x1080", ultrawide = "3440x1440"
    var frame: CGRect {
      self == .fhd ? CGRect(x: 1512, y: 0, width: 1920, height: 1080) : CGRect(x: 1512, y: 0, width: 3440, height: 1440)
    }
  }

  private func settings() -> AppSettings {
    AppSettings(defaults: UserDefaults(suiteName: "qs-external-\(UUID().uuidString)")!)
  }

  /// The geometry the shell builds for a display with no camera housing, from default settings.
  private func defaultGeometry(_ display: Display) -> NotchGeometry {
    let prefs = settings()
    return NotchGeometry.make(screenFrame: display.frame, hardwareNotch: nil,
                              style: prefs.shellExternalStyle, tuning: .current(prefs))
  }

  @Test func defaultsPickTheFloatingPillAlwaysShown() {
    let prefs = settings()
    #expect(prefs.shellExternalStyle == .island)
    #expect(prefs.shellExternalVisibility == .always)
    #expect(!prefs.shellHideInMissionControl)
    for display in Display.allCases {
      let geometry = defaultGeometry(display)
      #expect(geometry.isFloating)
      #expect(geometry.collapsedSize.width == NotchGeometry.islandClosedWidth)
      #expect(geometry.topInset == NotchGeometry.islandTopInset)
    }
  }

  private func render(_ name: String, display: Display, expanded: Bool = false, hovered: Bool = false,
                      height: CGFloat, nowPlaying: NowPlayingModel) async throws {
    let presentation = NotchPresentation()
    var geo = defaultGeometry(display)
    geo.hudHovered = hovered
    presentation.geometry = geo
    presentation.isExpanded = expanded
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let view = NotchShelfView(
      presentation: presentation, store: ShelfStore(directory: directory), nowPlaying: nowPlaying,
      calls: CallActivityModel(accessibilityTrusted: { false }), recording: ScreenRecordingModel(probe: { nil }),
      timers: NativeTimerModel(), tray: FileTrayStore(directory: directory.appendingPathComponent("tray")),
      homeWidgets: HomeWidgetStore(widgets: [.clock, .timer, .stats], persist: { _ in }),
      notifications: NotificationHUDModel(settings: settings()), glances: IslandGlanceModel(settings: settings()),
      theme: IslandTheme(surface: .dynamicGlass), weather: WeatherStore(settings: settings()),
      playingNext: IslandRedesignRenderTests.queue())
    let size = CGSize(width: 900, height: height)
    let wallpaper = IslandRedesignRenderTests.wallpaper(size: size)
    let root = ZStack(alignment: .top) {
      Image(nsImage: wallpaper).resizable().frame(width: size.width, height: size.height)
      // The external display's menu bar, for scale.
      Rectangle().fill(Color.black.opacity(0.35)).frame(height: 25)
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
    try await Task.sleep(for: .milliseconds(1400))
    host.layoutSubtreeIfNeeded()
    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    let png = try #require(bitmap.representation(using: .png, properties: [:]))
    let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().appendingPathComponent(".renders")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try png.write(to: dir.appendingPathComponent("external-\(display.rawValue)-\(name).png"))
  }

  private func player(playing: Bool) async -> NowPlayingModel {
    let model = NowPlayingModel(provider: ExternalRenderPlayer(known: playing), enabledSources: playing ? [.music] : [])
    if playing { await model.refreshNow() }
    return model
  }

  @Test(arguments: Display.allCases) func idleClosedAndOpen(display: Display) async throws {
    let quiet = await player(playing: false)
    try await render("idle-closed", display: display, height: 90, nowPlaying: quiet)
    try await render("idle-open", display: display, expanded: true, height: 300, nowPlaying: quiet)
  }

  @Test(arguments: Display.allCases) func musicClosedAndOpen(display: Display) async throws {
    let music = await player(playing: true)
    try await render("music-closed", display: display, height: 90, nowPlaying: music)
    try await render("music-open", display: display, expanded: true, height: 300, nowPlaying: music)
  }

  @Test(arguments: Display.allCases) func volumeHUDStripAndCard(display: Display) async throws {
    IslandFlashCenter.shared.show("Volume", symbol: "speaker.wave.2.fill", tint: .green, value: 0.62,
                                  duration: 600, kind: .volume)
    defer { IslandFlashCenter.shared.dismiss() }
    let quiet = await player(playing: false)
    try await render("hud-strip", display: display, height: 90, nowPlaying: quiet)
    try await render("hud-card", display: display, hovered: true, height: 150, nowPlaying: quiet)
  }
}

private struct ExternalRenderPlayer: NowPlayingProviding {
  var known: Bool
  func connect(_ source: NowPlayingSource) async throws {}
  func snapshot(_ source: NowPlayingSource) async throws -> NowPlayingSnapshot? {
    guard known else { return nil }
    return NowPlayingSnapshot(source: .music, title: "Kill Bill", artist: "SZA", album: "SOS", duration: 153,
                              position: 69, isPlaying: true)
  }
  func perform(_ command: NowPlayingCommand, expected: NowPlayingSnapshot, token: NowPlayingActionToken) async throws {}
}
