import AppKit
import SwiftUI
import Testing

@testable import Brim

/// Renders the whole closed/open island through `NotchShelfView` in every state the shell wires up, on a
/// notched display and on the island-pill style. PNGs land in `.renders/` for a visual check.
@MainActor
@Suite(.serialized)
struct IslandShellIntegrationRenderTests {
  enum Style: String, CaseIterable { case pill, notch }

  private let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)

  private func geometry(_ style: Style) -> NotchGeometry {
    style == .notch
      ? NotchGeometry(screenFrame: screen, notchWidth: 184, notchHeight: 32)
      : NotchGeometry.dynamicIsland(screenFrame: screen)
  }

  private func settings() -> AppSettings {
    AppSettings(defaults: UserDefaults(suiteName: "qs-shell-\(UUID().uuidString)")!)
  }

  private func quietPlayer() -> NowPlayingModel {
    NowPlayingModel(provider: ShellRenderPlayer(playing: false), enabledSources: [])
  }

  private func render(
    _ name: String, style: Style, height: CGFloat = 110, hovered: Bool = false, expanded: Bool = false,
    notificationOpen: Bool = false, belowNotch: Bool = false, nowPlaying: NowPlayingModel? = nil,
    notifications: NotificationHUDModel? = nil, glances: IslandGlanceModel? = nil, page: IslandPage = .home
  ) async throws {
    let presentation = NotchPresentation()
    presentation.navigate(to: .showing(page))
    var geo = geometry(style)
    geo.hudHovered = hovered
    geo.hudPlacement = belowNotch ? .belowNotch : .besideNotch
    presentation.geometry = geo
    presentation.isExpanded = expanded
    presentation.expandedForNotification = notificationOpen
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let view = NotchShelfView(
      presentation: presentation, store: ShelfStore(directory: directory),
      nowPlaying: nowPlaying ?? quietPlayer(), calls: CallActivityModel(accessibilityTrusted: { false }),
      recording: ScreenRecordingModel(probe: { nil }), timers: NativeTimerModel(),
      notifications: notifications ?? NotificationHUDModel(settings: settings()),
      glances: glances ?? IslandGlanceModel(settings: settings()),
      // A canned queue: the shared model would run AppleScript against the real Music app.
      playingNext: PlayingNextModel(read: { _ in "" }, perform: { _ in "" }, fetchArtwork: { _ in nil }))
    let size = CGSize(width: 740, height: height)
    let top = geo.topInset
    let host = NSHostingView(
      rootView: view.padding(.top, top).frame(width: size.width, height: size.height, alignment: .top)
        .background(LinearGradient(colors: [Color(white: 0.30), Color(white: 0.18)], startPoint: .top, endPoint: .bottom)))
    let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    defer { window.close() }
    host.frame = CGRect(origin: .zero, size: size)
    host.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(1200))
    host.layoutSubtreeIfNeeded()
    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    let png = try #require(bitmap.representation(using: .png, properties: [:]))
    try png.write(to: rendersDirectory().appendingPathComponent("shell-\(name)-\(style.rawValue).png"))
  }

  private func rendersDirectory() throws -> URL {
    let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().appendingPathComponent(".renders")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  private func hud(_ flash: @MainActor () -> Void, then body: () async throws -> Void) async throws {
    flash()
    defer { IslandFlashCenter.shared.dismiss() }
    try await body()
  }

  @Test(arguments: Style.allCases) func idleWithGlances(style: Style) async throws {
    let prefs = settings()
    prefs.glanceLeft = IslandGlance.clock.rawValue
    prefs.glanceRight = IslandGlance.battery.rawValue
    let glances = IslandGlanceModel(settings: prefs, battery: (82, false))
    try await render("idle-glances", style: style, glances: glances)
  }

  @Test(arguments: Style.allCases) func idleWithoutGlancesStaysPlain(style: Style) async throws {
    try await render("idle", style: style)
  }

  @Test(arguments: Style.allCases) func volumeStrip(style: Style) async throws {
    try await hud({
      IslandFlashCenter.shared.show("Volume", symbol: "speaker.wave.2.fill", tint: .green, value: 0.62,
                                    duration: 600, kind: .volume)
    }, then: { try await render("volume-strip", style: style) })
  }

  @Test(arguments: Style.allCases) func volumeCard(style: Style) async throws {
    try await hud({
      IslandFlashCenter.shared.show("Volume", symbol: "speaker.wave.2.fill", tint: .green, value: 0.62,
                                    duration: 600, kind: .volume)
    }, then: { try await render("volume-card", style: style, height: 150, hovered: true) })
  }

  @Test func volumeStripHangingBelowTheNotch() async throws {
    try await hud({
      IslandFlashCenter.shared.show("Volume", symbol: "speaker.wave.2.fill", tint: .green, value: 0.62,
                                    duration: 600, kind: .volume)
    }, then: { try await render("volume-strip-below", style: .notch, height: 120, belowNotch: true) })
  }

  @Test(arguments: Style.allCases) func driveCardWithEject(style: Style) async throws {
    try await hud({
      IslandFlashCenter.shared.show(
        "T7 Shield", symbol: "externaldrive.fill", duration: 600, kind: .drive, detail: "Drive connected · 1 TB",
        action: HUDAction(title: "Eject", symbol: "eject.fill") {}, shortTitle: "Drive")
    }, then: { try await render("drive-card", style: style, height: 170, hovered: true) })
  }

  @Test(arguments: Style.allCases) func notificationCompactAndOpen(style: Style) async throws {
    let prefs = settings()
    prefs.notificationHUDEnabled = true
    let model = NotificationHUDModel(settings: prefs)
    model.ingest(NotificationContent(
      bundleID: "com.apple.MobileSMS", appName: "Messages", title: "Anna Kowalski",
      body: "Are we still on for dinner at 8? I booked the little place by the river."))
    #expect(model.current != nil)
    try await render("notification-compact", style: style, notifications: model)
    try await render("notification-open", style: style, height: 210, expanded: true, notificationOpen: true,
                     notifications: model)
    model.stop()
  }

  @Test(arguments: Style.allCases) func musicWithTitle(style: Style) async throws {
    let settings = AppSettings.shared
    let saved = (settings.notchTrackTitle, settings.keepSongNameVisible)
    settings.notchTrackTitle = true
    settings.keepSongNameVisible = true
    defer { (settings.notchTrackTitle, settings.keepSongNameVisible) = saved }
    let music = NowPlayingModel(provider: ShellRenderPlayer(playing: true), enabledSources: [.music])
    await music.refreshNow()
    try await render("music-title", style: style, nowPlaying: music)
  }

  /// The open player: the cover keeps its side inset inside the shape's shoulders.
  @Test(arguments: Style.allCases) func musicOpen(style: Style) async throws {
    let music = NowPlayingModel(provider: ShellRenderPlayer(playing: true), enabledSources: [.music])
    await music.refreshNow()
    try await render("music-open", style: style, height: 260, expanded: true, nowPlaying: music, page: .music)
  }

  @Test(arguments: Style.allCases) func agentNeedsInput(style: Style) async throws {
    CodingAgentModel.shared.setSessionsForPreview([
      CodingAgentSession(tool: .claude, model: nil, state: .needsInput("Approve: Bash"), steps: [],
                         lastMessage: nil, outputTokens: 0, contextTokens: 0, turns: 1, started: nil, updated: .now)
    ])
    defer { CodingAgentModel.shared.setSessionsForPreview([]) }
    try await render("agent-needs-input", style: style)
  }
}

private struct ShellRenderPlayer: NowPlayingProviding {
  var playing: Bool
  func connect(_ source: NowPlayingSource) async throws {}
  func snapshot(_ source: NowPlayingSource) async throws -> NowPlayingSnapshot? {
    NowPlayingSnapshot(source: .music, title: "Midnight City", artist: "M83", album: "Hurry Up", duration: 244,
                       position: 60, isPlaying: playing)
  }
  func perform(_ command: NowPlayingCommand, expected: NowPlayingSnapshot, token: NowPlayingActionToken) async throws {}
}
