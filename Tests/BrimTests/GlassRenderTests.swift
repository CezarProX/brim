import AppKit
import SwiftUI
import Testing

@testable import Brim

/// Captures the real glass (Liquid Glass, AppKit materials, vibrancy) that `cacheDisplay` and
/// `ImageRenderer` cannot draw. Each window holds its own colourful wallpaper, its glass blurs
/// within the window, and it sits one level below the desktop picture so nothing shows on screen
/// while `screencapture -l` grabs it by window ID. PNGs land in `.renders/glass-*.png`.
/// Without Screen Recording permission `screencapture` fails and the test records nothing.
@MainActor
@Suite(.serialized)
struct GlassRenderTests {
  // MARK: Settings

  @Test(arguments: [
    (SettingsPane.general, "dark"), (.island, "dark"), (.widgets, "dark"), (.general, "light"), (.capture, "light"),
  ])
  func settingsWindow(_ pane: SettingsPane, appearance: String) async throws {
    let wallpaper = IslandRedesignRenderTests.wallpaper(size: SettingsWindowLayout.defaultSize)
    let window = SettingsWindowController.makeWindow(
      rootView: SettingsRootView(destination: SettingsDestination(pane)), backdrop: wallpaper)
    window.appearance = NSAppearance(named: appearance == "light" ? .aqua : .darkAqua)
    try await capture(window, file: "glass-settings-\(pane.renderName)-\(appearance)", wait: 1400)
  }

  // MARK: Floating panels

  @Test func floatingPanels() async throws {
    let services = FakeThumbnailServices()
    let thumbnail = ThumbnailCardModel(
      id: UUID(), image: ThumbnailFixtures.image(size: CGSize(width: 640, height: 400)), corner: .bottomRight,
      delay: 0, services: services)
    thumbnail.present()
    let tour = IslandTourCardModel()
    tour.step = .home
    tour.context = IslandTourContext(hasTrack: true)
    tour.visible = true
    let targets = [DropTarget.keep, .convert, .airDrop, .localSend]
    let actionsSize = FloatingTrayLayout.quickActionsSize(tileCount: targets.count)
    let content = HStack(alignment: .top, spacing: 28) {
      VStack(spacing: 28) {
        ThumbnailCardView(model: thumbnail, services: services)
        QuickActionsView(targets: targets, size: actionsSize) { _, _ in }
      }
      VStack(spacing: 28) {
        BasketView(model: BasketModel(), registry: FloatingTrayRegistry(), number: 1, close: {})
        IslandTourCard(model: tour)
      }
      AgentQuestionCardView(request: Self.question())
    }
    .padding(36)
    try await captureView(content, size: CGSize(width: 1240, height: 860), file: "glass-panels")
  }

  @Test(arguments: [false, true])
  func floatingPanelsReduceTransparency(_ increaseContrast: Bool) async throws {
    let content = HStack(spacing: 28) {
      AgentQuestionCardView(request: Self.question())
      Text("Reduce Transparency").font(.title2.weight(.semibold)).foregroundStyle(.white)
        .padding(28).glassPanel(radius: 22)
    }
    .padding(36)
    .environment(
      \.glassPreferencesOverride, GlassPreferences(reduceTransparency: !increaseContrast, increaseContrast: increaseContrast))
    try await captureView(
      content, size: CGSize(width: 820, height: 420),
      file: increaseContrast ? "glass-panels-increase-contrast" : "glass-panels-reduce-transparency")
  }

  // MARK: Island

  @Test(arguments: [IslandSurfaceStyle.dynamicGlass, .liquidGlass])
  func islandHome(_ surface: IslandSurfaceStyle) async throws {
    let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let presentation = NotchPresentation()
    let geometry = NotchGeometry(screenFrame: screen, notchWidth: 184, notchHeight: 32)
    presentation.geometry = geometry
    presentation.isExpanded = true
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let settings = AppSettings(defaults: UserDefaults(suiteName: "qs-glass-\(UUID().uuidString)")!)
    let view = NotchShelfView(
      presentation: presentation, store: ShelfStore(directory: directory),
      nowPlaying: NowPlayingModel(provider: QuietPlayer(), enabledSources: []),
      calls: CallActivityModel(accessibilityTrusted: { false }), recording: ScreenRecordingModel(probe: { nil }),
      timers: NativeTimerModel(), tray: FileTrayStore(directory: directory.appendingPathComponent("tray")),
      homeWidgets: HomeWidgetStore(widgets: [.clock, .timer, .stats], persist: { _ in }),
      notifications: NotificationHUDModel(settings: settings), glances: IslandGlanceModel(settings: settings),
      theme: IslandTheme(surface: surface), weather: WeatherStore(settings: settings),
      playingNext: IslandRedesignRenderTests.queue())
    let content = view.padding(.top, geometry.topInset).frame(maxHeight: .infinity, alignment: .top)
    try await captureView(content, size: CGSize(width: 860, height: 330), file: "glass-island-home-\(surface.rawValue)", wait: 1800)
  }

  // MARK: Capture

  private static func question() -> AgentQuestionRequest {
    let object: [String: Any] = [
      "agent": "claude", "cwd": "/Users/me/screenshot app", "sessionId": "s",
      "question": "The release build is green. How do you want to ship the editor changes?",
      "options": [["label": "Ship it now (Recommended)", "description": "Tag 1.4 and publish"], ["label": "Wait until Monday"]],
    ]
    return try! AgentQuestionRequest.parse(try! JSONSerialization.data(withJSONObject: object))
  }

  /// Hosts `content` over the wallpaper in a borderless window and captures it.
  private func captureView<V: View>(_ content: V, size: CGSize, file: String, wait: Int = 1100) async throws {
    let wallpaper = IslandRedesignRenderTests.wallpaper(size: size)
    let root = ZStack(alignment: .topLeading) {
      Image(nsImage: wallpaper).resizable().frame(width: size.width, height: size.height)
      content.frame(width: size.width, height: size.height, alignment: .topLeading)
    }
    .environment(\.glassBlendsWithinWindow, true)
    .environment(\.colorScheme, .dark)
    let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = NSHostingView(rootView: root)
    window.appearance = NSAppearance(named: .darkAqua)
    try await capture(window, file: file, wait: wait)
  }

  private func capture(_ window: NSWindow, file: String, wait: Int) async throws {
    window.isReleasedWhenClosed = false
    // Below the desktop picture: composited (so capturable) but never visible.
    window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) - 1)
    window.ignoresMouseEvents = true
    window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
    defer { window.orderOut(nil); window.close() }
    window.setFrameOrigin(NSPoint(x: 40, y: 40))
    window.orderFrontRegardless()
    try await Task.sleep(for: .milliseconds(wait))

    let url = try DropletRender.url("\(file).png")
    try? FileManager.default.removeItem(at: url)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    process.arguments = ["-x", "-o", "-l\(window.windowNumber)", url.path]
    try process.run()
    process.waitUntilExit()
    if process.terminationStatus == 0, FileManager.default.fileExists(atPath: url.path) {
      let image = try #require(NSImage(contentsOf: url))
      #expect(image.size.width > 200)
    }
  }
}

private struct QuietPlayer: NowPlayingProviding {
  func connect(_ source: NowPlayingSource) async throws {}
  func snapshot(_ source: NowPlayingSource) async throws -> NowPlayingSnapshot? { nil }
  func perform(_ command: NowPlayingCommand, expected: NowPlayingSnapshot, token: NowPlayingActionToken) async throws {}
}

/// The navigation capsule fades in with the island. An AppKit blur once ignored SwiftUI's fade in the
/// live island (a grey pill before it opened), so on macOS 26 the capsule uses SwiftUI's own glass.
/// This guards that, early in a slow fade-in, that glass is still almost invisible. Limitation: in
/// this in-window harness an AppKit material also follows the fade, so the original live bug is not
/// reproduced here.
@MainActor
@Suite(.serialized)
struct GlassCapsuleFadeTests {
  final class Gate: ObservableObject { @Published var shown = false }

  @Test func capsuleGlassFollowsTheFadeIn() async throws {
    guard GlassSupport.hasLiquidGlass else { return }
    let bare = try await Self.capture { EmptyView() }
    let early = try await Self.capture { DynamicGlassCapsuleSurface(shape: Capsule()) }
    let settled = try await Self.capture(after: 2600) { DynamicGlassCapsuleSurface(shape: Capsule()) }
    guard let bare, let early, let settled else { return }  // No Screen Recording permission.
    let x = bare.pixelsWide / 2, y = bare.pixelsHigh / 2
    func gray(_ rep: NSBitmapImageRep) -> Double {
      let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB)
      return Double((c?.redComponent ?? 0) + (c?.greenComponent ?? 0) + (c?.blueComponent ?? 0)) / 3
    }
    let full = abs(gray(settled) - gray(bare))
    #expect(full > 0.05, "the settled capsule draws something")
    #expect(abs(gray(early) - gray(bare)) < full * 0.35, "early \(gray(early)) bare \(gray(bare)) settled \(gray(settled))")
  }

  private struct Stage<Capsule: View>: View {
    @ObservedObject var gate: Gate
    let capsule: Capsule
    var body: some View {
      ZStack {
        Color(red: 0.95, green: 0.6, blue: 0.3)
        if gate.shown {
          capsule.frame(width: 160, height: 44).transition(.opacity.animation(.linear(duration: 2.4)))
        }
      }
      .environment(\.glassBlendsWithinWindow, true)
    }
  }

  /// Shows the window, starts a 2.4 s fade-in of `capsule`, and captures `after` ms into it.
  private static func capture<V: View>(after: Int = 150, @ViewBuilder _ capsule: () -> V) async throws -> NSBitmapImageRep? {
    let size = CGSize(width: 240, height: 120)
    let gate = Gate()
    let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = NSHostingView(rootView: Stage(gate: gate, capsule: capsule()).frame(width: size.width, height: size.height))
    window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) - 1)
    window.ignoresMouseEvents = true
    defer { window.orderOut(nil); window.close() }
    window.setFrameOrigin(NSPoint(x: 40, y: 40))
    window.orderFrontRegardless()
    try await Task.sleep(for: .milliseconds(500))
    gate.shown = true
    try await Task.sleep(for: .milliseconds(after))
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("glass-fade-\(UUID().uuidString).png")
    defer { try? FileManager.default.removeItem(at: url) }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    process.arguments = ["-x", "-o", "-l\(window.windowNumber)", url.path]
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0, let data = try? Data(contentsOf: url) else { return nil }
    return NSBitmapImageRep(data: data)
  }
}
