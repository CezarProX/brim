import AppKit
import SwiftUI
import Testing

@testable import Brim

/// Renders the Widgets page (every tile, page by page as the grid scrolls) and each tool the
/// feature packages added, opened inside the island on a notched display. PNGs land in
/// `.renders/tools-*.png`.
@MainActor
@Suite(.serialized)
struct WidgetToolsRenderTests {
  private let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)

  private func settings() -> AppSettings {
    AppSettings(defaults: UserDefaults(suiteName: "qs-tools-\(UUID().uuidString)")!)
  }

  private func write(_ view: some View, size: CGSize, name: String) async throws {
    let wallpaper = IslandRedesignRenderTests.wallpaper(size: size)
    let root = ZStack(alignment: .top) {
      Image(nsImage: wallpaper).resizable().frame(width: size.width, height: size.height)
      view.frame(width: size.width, height: size.height, alignment: .top)
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
    try await Task.sleep(for: .milliseconds(1500))
    host.layoutSubtreeIfNeeded()
    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    let png = try #require(bitmap.representation(using: .png, properties: [:]))
    let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().appendingPathComponent(".renders")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try png.write(to: dir.appendingPathComponent("tools-\(name).png"))
  }

  private func island(_ configure: (NotchPresentation) -> Void) -> some View {
    let presentation = NotchPresentation()
    presentation.geometry = NotchGeometry(screenFrame: screen, notchWidth: 184, notchHeight: 32)
    presentation.isExpanded = true
    configure(presentation)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    return NotchShelfView(
      presentation: presentation, store: ShelfStore(directory: directory),
      nowPlaying: NowPlayingModel(provider: QuietPlayer(), enabledSources: []),
      calls: CallActivityModel(accessibilityTrusted: { false }), recording: ScreenRecordingModel(probe: { nil }),
      timers: NativeTimerModel(), tray: FileTrayStore(directory: directory.appendingPathComponent("tray")),
      homeWidgets: HomeWidgetStore(widgets: [.clock, .timer, .stats], persist: { _ in }),
      notifications: NotificationHUDModel(settings: settings()), glances: IslandGlanceModel(settings: settings()),
      theme: IslandTheme(surface: .dynamicGlass), weather: WeatherStore(settings: settings()),
      playingNext: IslandRedesignRenderTests.queue())
  }

  /// The grid scrolls two rows at a time; each chunk of eight tiles is one scroll position.
  @Test func everyWidgetTilePageByPage() async throws {
    try await write(island { $0.navigate(to: .showing(.widgets)) }, size: CGSize(width: 860, height: 420), name: "widgets-shell")
    let tiles = IslandWidgetTile.visible(hasRecordingResult: true)
    for (index, start) in stride(from: 0, to: tiles.count, by: 8).enumerated() {
      let chunk = Array(tiles[start..<min(tiles.count, start + 8)])
      let page = IslandWidgetsPage(
        opened: nil, center: .shared, store: ShelfStore(directory: FileManager.default.temporaryDirectory),
        nowPlaying: NowPlayingModel(provider: QuietPlayer(), enabledSources: []), outputs: .shared,
        outputDrawer: .constant(false), fixedTiles: chunk, open: { _ in })
        .frame(width: IslandPageLayout.widgetsWidth, height: IslandPageLayout.widgetsHeight(tiles: chunk.count))
        .background(Color.black.opacity(0.82), in: RoundedRectangle(cornerRadius: 40, style: .continuous))
        .padding(.top, 20)
      try await write(page, size: CGSize(width: 640, height: 330), name: "widgets-page\(index + 1)")
    }
  }

  static let opened: [IslandWidgetTile] = [
    .termiNotch, .teleprompter, .textCapture, .dropClip, .audioControl, .airPlayRooms, .timer, .notes, .obsidian,
    .calendar, .xcodeBuilds,
  ]

  @Test(arguments: opened) func openedTool(tile: IslandWidgetTile) async throws {
    let height = 32 + min(IslandNavigationLayout.maxPageHeight, tile.openHeight) + 80
    try await write(island { $0.navigate(to: .opening(tile)) }, size: CGSize(width: 860, height: height), name: "open-\(tile.rawValue)")
  }
}

private struct QuietPlayer: NowPlayingProviding {
  func connect(_ source: NowPlayingSource) async throws {}
  func snapshot(_ source: NowPlayingSource) async throws -> NowPlayingSnapshot? { nil }
  func perform(_ command: NowPlayingCommand, expected: NowPlayingSnapshot, token: NowPlayingActionToken) async throws {}
}
