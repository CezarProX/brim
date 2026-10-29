import AppKit
import SwiftUI
import Testing

@testable import Brim

/// Renders the four island apps in each state, inside the same frame the opened widget uses, to
/// .renders/apps-<app>-<state>.png.
@MainActor
@Suite(.serialized)
struct IslandDropletAppsRenderTests {
  private struct Frame<Content: View>: View {
    let tile: IslandWidgetTile
    @ViewBuilder var content: Content
    var body: some View {
      VStack(alignment: .leading, spacing: IslandSpace.s) {
        HStack(spacing: 10) {
          Image(systemName: "chevron.left").font(.system(size: 11, weight: .bold)).foregroundStyle(IslandInk.primary)
            .frame(width: 26, height: 26).background(IslandFill.raised, in: Circle())
          IslandWidgetIcon(tile: tile, size: 22)
          VStack(alignment: .leading, spacing: 0) {
            Text(tile.title).font(IslandFont.title).foregroundStyle(IslandInk.primary)
            if let subtitle = tile.subtitle { Text(subtitle).font(IslandFont.body).foregroundStyle(IslandInk.secondary).lineLimit(1) }
          }
          Spacer(minLength: 0)
        }
        .frame(height: 34)
        content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
      }
      .padding(.horizontal, 28).padding(.top, 8).padding(.bottom, 20)
      .frame(width: IslandPageLayout.widgetsWidth, height: tile.openHeight)
      .background(Color.black, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
      .padding(24)
    }
  }

  private func render<V: View>(_ tile: IslandWidgetTile, _ name: String, @ViewBuilder _ content: () -> V) async throws {
    let view = Frame(tile: tile, content: content)
    try await DropletRender.png(
      view, size: CGSize(width: IslandPageLayout.widgetsWidth + 48, height: tile.openHeight + 48),
      name: "apps-\(name).png", background: Color(white: 0.3))
  }

  // MARK: Emoji

  @Test func emoji() async throws {
    try await render(.emojiPicker, "emoji-default") { EmojiIslandView(onInserted: {}) }
  }

  @Test func emojiSearch() async throws {
    struct Searching: View {
      @State var ready = false
      var body: some View { EmojiIslandView(onInserted: {}) }
    }
    // Typing into the field is not scriptable in a render, so the search state is shown through a model.
    let model = EmojiPickerModel(settings: DropletRender.isolatedSettings(), columns: 12)
    model.query = "heart"
    try await render(.emojiPicker, "emoji-search") { EmojiModelPreview(model: model) }
  }

  // MARK: Launcher

  @Test func launcher() async throws {
    AppSettings.shared.thunderstormEnabled = false
    LauncherEnabledState.shared.refresh()
    try await render(.launcher, "launcher-firstrun") { LauncherIslandView() }
    AppSettings.shared.thunderstormEnabled = true
    LauncherEnabledState.shared.refresh()
    try await render(.launcher, "launcher-empty") { LauncherIslandView() }
    AppSettings.shared.thunderstormEnabled = false
    LauncherEnabledState.shared.refresh()
  }

  @Test func launcherResults() async throws {
    let settings = DropletRender.isolatedSettings()
    let apps = ["Safari", "Slack", "Spotify", "Sketch", "System Settings"].map {
      InstalledApp(name: $0, url: URL(fileURLWithPath: "/Applications/\($0).app"), bundleID: "com.example.\($0)")
    }
    let model = ThunderstormModel(settings: settings, apps: apps)
    model.query = "s"
    try await render(.launcher, "launcher-results") { LauncherResultsPreview(model: model) }
    model.query = "12 * (3 + 4) + 20% of 50"
    try await render(.launcher, "launcher-calc") { LauncherResultsPreview(model: model) }
  }

  // MARK: Cleaner

  private func cleanerFixture() throws -> (URL, CleanerModel, [InstalledApp]) {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("cleaner-render-\(UUID().uuidString)")
    let lib = root.appendingPathComponent("Library")
    for path in ["Application Support/com.example.Slack", "Caches/com.example.Slack", "Caches/Slack", "Containers/com.example.Slack", "Logs/Slack", "Caches/Spotify", "Caches/Figma"] {
      try FileManager.default.createDirectory(at: lib.appendingPathComponent(path), withIntermediateDirectories: true)
    }
    try Data(repeating: 1, count: 4_000_000).write(to: lib.appendingPathComponent("Application Support/com.example.Slack/db"))
    try Data(repeating: 1, count: 900_000).write(to: lib.appendingPathComponent("Caches/com.example.Slack/blob"))
    try Data(repeating: 1, count: 90_000).write(to: lib.appendingPathComponent("Caches/Slack/x"))
    try Data(repeating: 1, count: 2_500_000).write(to: lib.appendingPathComponent("Caches/Spotify/x"))
    try Data(repeating: 1, count: 700_000).write(to: lib.appendingPathComponent("Caches/Figma/x"))
    let apps = ["Slack", "Spotify", "Figma", "Notion", "Docker", "Zoom"].map {
      InstalledApp(name: $0, url: URL(fileURLWithPath: "/Applications/\($0).app"), bundleID: "com.example.\($0)")
    }
    return (root, CleanerModel(home: root, apps: apps, trasher: { _ in }), apps)
  }

  @Test func cleaner() async throws {
    let (root, model, apps) = try cleanerFixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let state = CleanerEnabledState(settings: DropletRender.isolatedSettings())
    try await render(.cleaner, "cleaner-firstrun") { CleanerIslandView(model: model, settings: state) }
    state.enable()
    try await render(.cleaner, "cleaner-apps") { CleanerIslandView(model: model, settings: state) }
    model.choose(apps[0])
    try await Task.sleep(for: .milliseconds(800))
    try await render(.cleaner, "cleaner-leftovers") { CleanerIslandView(model: model, settings: state) }
    model.selectSuggested()
    try await render(.cleaner, "cleaner-selected") { CleanerIslandView(model: model, settings: state) }
    model.requestMove()
    #expect(model.confirming)
    try await render(.cleaner, "cleaner-confirm") { CleanerIslandView(model: model, settings: state) }
    model.confirmMove()
    try await render(.cleaner, "cleaner-done") { CleanerIslandView(model: model, settings: state) }
    model.leaveApp()
    model.switchMode(.caches)
    try await Task.sleep(for: .milliseconds(800))
    try await render(.cleaner, "cleaner-caches") { CleanerIslandView(model: model, settings: state) }
  }

  // MARK: Menu bar

  @Test func menuBar() async throws {
    try await render(.menuBarManager, "menubar-off") { MenuBarIslandView() }
    try await render(.menuBarManager, "menubar-showing") { MenuBarIslandView(previewRunning: true, previewCollapsed: false) }
    try await render(.menuBarManager, "menubar-hidden") { MenuBarIslandView(previewRunning: true, previewCollapsed: true) }
    try await render(.menuBarManager, "menubar-notice") {
      MenuBarIslandView(previewRunning: true, previewCollapsed: false, previewNotice: "Hold ⌘ and drag the divider to the left of the arrow first.")
    }
  }
}

/// The emoji grid driven by a model the test prepared (the real view owns its own).
@MainActor
private struct EmojiModelPreview: View {
  @ObservedObject var model: EmojiPickerModel
  var body: some View {
    VStack(spacing: 8) {
      HStack { Image(systemName: "magnifyingglass"); Text(model.query); Spacer() }
        .padding(.horizontal, 12).frame(height: 34).background(IslandFill.subtle, in: Capsule())
      LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 12), spacing: 2) {
        ForEach(Array(model.visible.prefix(36).enumerated()), id: \.offset) { _, item in
          Text(model.display(item)).font(.system(size: 23)).frame(height: 34)
        }
      }
    }
  }
}

@MainActor
private struct LauncherResultsPreview: View {
  @ObservedObject var model: ThunderstormModel
  var body: some View {
    VStack(spacing: 2) {
      Text(model.query).font(.system(size: 16)).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14)
        .frame(height: 38).background(IslandFill.subtle, in: Capsule())
      ForEach(Array(model.results.prefix(4).enumerated()), id: \.element.id) { index, result in
        ThunderRow(result: result, index: index, selected: index == 0, confirming: false)
      }
    }
  }
}

