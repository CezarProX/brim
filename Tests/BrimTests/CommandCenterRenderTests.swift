import AppKit
import SwiftUI
import Testing

@testable import Brim

/// Renders the Command Center (pages and edit mode) and the onboarding tour to `.renders/`.
@MainActor
@Suite(.serialized)
struct CommandCenterRenderTests {
  private func store(edit: Bool = false) -> CommandCenterStore {
    let defaults = UserDefaults(suiteName: "cc.render.\(UUID().uuidString)")!
    let store = CommandCenterStore(settings: AppSettings(defaults: defaults))
    store.isEditing = edit
    return store
  }

  private func view(page: Int, store: CommandCenterStore, playing: NowPlayingModel) -> some View {
    let pager = CommandCenterPageState()
    pager.page = page
    return CommandCenterView(store: store, pager: pager,
                             models: CommandCenterModels(playing: playing, upcomingOverride: OnboardingSamples.upcoming()),
                             animatesEntrance: false)
  }

  @Test func commandCenterPagesRender() async throws {
    let playing = await OnboardingSamples.nowPlaying()
    let store = store()
    #expect(store.pageCount >= 2)
    for page in 0..<2 {
      let bitmap = try await render(view(page: page, store: store, playing: playing), name: "command-center-page\(page + 1)",
                                    size: CommandCenterView.size, padding: 30)
      #expect(bright(bitmap, CGRect(x: 40, y: 40, width: 300, height: 250)) > 40, "page \(page + 1) draws text and glyphs")
    }
  }

  @Test func commandCenterEditModeRenders() async throws {
    let playing = await OnboardingSamples.nowPlaying()
    let bitmap = try await render(view(page: 0, store: store(edit: true), playing: playing), name: "command-center-edit",
                                  size: CommandCenterView.size, padding: 30)
    #expect(bright(bitmap, CGRect(x: 40, y: 40, width: 300, height: 250)) > 40)
  }

  // MARK: helpers

  private func render<V: View>(_ content: V, name: String, size: CGSize, padding: CGFloat = 0, wallpaper: Bool = true) async throws -> NSBitmapImageRep {
    let backdrop = LinearGradient(colors: [Color(red: 0.12, green: 0.2, blue: 0.5), Color(red: 0.75, green: 0.45, blue: 0.6)],
                                  startPoint: .topLeading, endPoint: .bottomTrailing)
    let full = CGSize(width: size.width + padding * 2, height: size.height + padding * 2)
    let host = NSHostingView(rootView: content.padding(padding).frame(width: full.width, height: full.height)
      .background(wallpaper ? AnyView(backdrop) : AnyView(Color.clear)).preferredColorScheme(.dark))
    let window = NSWindow(contentRect: CGRect(origin: .zero, size: full), styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    defer { window.close() }
    host.frame = CGRect(origin: .zero, size: full)
    host.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(450))
    host.layoutSubtreeIfNeeded()
    host.displayIfNeeded()
    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(".renders")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    if let png = bitmap.representation(using: .png, properties: [:]) {
      try png.write(to: directory.appendingPathComponent("\(name).png"), options: .atomic)
    }
    return bitmap
  }

  private func bright(_ bitmap: NSBitmapImageRep, _ area: CGRect) -> Int {
    let scale = CGFloat(bitmap.pixelsWide) / max(1, bitmap.size.width)
    var count = 0
    for y in stride(from: Int(area.minY * scale), to: min(bitmap.pixelsHigh, Int(area.maxY * scale)), by: 2) {
      for x in stride(from: Int(area.minX * scale), to: min(bitmap.pixelsWide, Int(area.maxX * scale)), by: 2) {
        guard let c = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
        if c.redComponent > 0.8 && c.greenComponent > 0.8 && c.blueComponent > 0.8 { count += 1 }
      }
    }
    return count
  }
}
