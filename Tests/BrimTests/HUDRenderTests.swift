import AppKit
import SwiftUI
import Testing

@testable import Brim

/// Renders the HUD strips, cards and settings list to `.renders/` so the design can be looked at.
@MainActor
@Suite(.serialized)
struct HUDRenderTests {
  private static let metrics = HUDMetrics(notchWidth: 190, closedHeight: 32)

  private func flash(
    _ title: String, _ symbol: String, _ tint: Color, value: Double? = nil, kind: HUDKind,
    detail: String? = nil, action: HUDAction? = nil, short: String? = nil, elapsed: Date? = nil
  ) -> IslandFlash {
    IslandFlash(
      title: title, symbol: symbol, tint: tint, value: value, until: .distantFuture, kind: kind,
      detail: detail, elapsedSince: elapsed, action: action, shortTitle: short)
  }

  private func shell(_ flash: IslandFlash, expanded: Bool) -> some View {
    let size = Self.metrics.size(for: flash, expanded: expanded)
    return HUDMorphView(flash: flash, metrics: Self.metrics, expanded: expanded)
      .background(
        UnevenRoundedRectangle(bottomLeadingRadius: expanded ? 28 : 14, bottomTrailingRadius: expanded ? 28 : 14).fill(.black)
          .frame(width: size.width, height: size.height))
      .frame(width: Self.metrics.cardSize(for: flash).width + 20, height: Self.metrics.cardSize(for: flash).height + 14, alignment: .top)
      .background(LinearGradient(colors: [.indigo.opacity(0.7), .teal.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing))
      .environment(\.colorScheme, .dark)
  }

  private func write<V: View>(_ view: V, name: String) throws {
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    let image = try #require(renderer.nsImage)
    let tiff = try #require(image.tiffRepresentation)
    let png = try #require(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
    try png.write(to: try rendersDirectory().appendingPathComponent("\(name).png"))
  }

  private func rendersDirectory() throws -> URL {
    let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().appendingPathComponent(".renders")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  @Test func stripsAndCards() throws {
    let volume = flash("Volume", "speaker.wave.2.fill", .green, value: 0.41, kind: .volume)
    let bright = flash("Display", "sun.max.fill", .yellow, value: 0.69, kind: .brightness)
    let muted = flash("Muted", "speaker.slash.fill", .green, value: 0, kind: .volume)
    let quit = flash("Press ⌘Q again to quit Xcode", "command", .orange, kind: .quitGuard, short: "Quit Xcode?")
    let drive = flash(
      "T7 Shield", "externaldrive.fill", .white, kind: .drive, detail: "Drive connected · 1 TB",
      action: HUDAction(title: "Eject", symbol: "eject.fill") {}, short: "Drive")
    let vpn = flash("Work VPN", "lock.shield.fill", .green, kind: .vpn, detail: "VPN connected",
                    short: "VPN", elapsed: .now.addingTimeInterval(-725))
    let all = VStack(spacing: 10) {
      ForEach(Array([volume, bright, muted, quit, drive, vpn].enumerated()), id: \.offset) { _, item in
        HStack(spacing: 14) {
          shell(item, expanded: false)
          shell(item, expanded: true)
        }
      }
    }.padding(14).background(Color(white: 0.12))
    try write(all, name: "hud-strips-and-cards")
  }

  @Test func settingsSection() async throws {
    let size = CGSize(width: 640, height: 830)
    let view = Form { HUDSettingsSection() }.formStyle(.grouped).frame(width: size.width, height: size.height, alignment: .top)
      .background(Color(nsColor: .windowBackgroundColor)).environment(\.colorScheme, .dark)
    let host = NSHostingView(rootView: view)
    let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.appearance = NSAppearance(named: .darkAqua)
    window.contentView = host
    defer { window.close() }
    host.frame = CGRect(origin: .zero, size: size)
    host.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(600))
    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    let png = try #require(bitmap.representation(using: .png, properties: [:]))
    try png.write(to: try rendersDirectory().appendingPathComponent("hud-settings.png"))
  }
}
