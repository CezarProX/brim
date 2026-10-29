import AppKit
import SwiftUI
import Testing

@testable import Brim

/// Contact sheets of every feature icon (Home dock, Widgets grid, Settings sidebar), so real Apple
/// icons and the custom `AppleStyleIcon` art can be compared side by side. PNGs land in
/// `.renders/icons-*.png`; the custom art is drawn in both icon themes.
@MainActor
@Suite(.serialized)
struct FeatureIconRenderTests {
  @Test func homeDockIcons() async throws {
    let sheet = IconSheet(
      items: HomeWidget.allCases.map { ($0.title, $0.icon) }, size: 36, columns: 11, dark: true)
    try await render(sheet, name: "icons-home-dock.png")
  }

  @Test func widgetsGridIcons() async throws {
    let sheet = IconSheet(
      items: IslandWidgetTile.allCases.map { ($0.title, $0.icon) }, size: IslandWidgetGrid.iconSize, columns: 6,
      dark: true)
    try await render(sheet, name: "icons-widgets-grid.png")
  }

  @Test func settingsSidebarIcons() async throws {
    let items = SettingsPane.allCases.map { ($0.rawValue, $0.icon) }
    try await render(IconSheet(items: items, size: 20, columns: 7, dark: false), name: "icons-settings-20.png")
    try await render(IconSheet(items: items, size: 52, columns: 7, dark: false), name: "icons-settings-52.png")
  }

  /// The custom art alone, in the light (colorful) and dark icon themes.
  @Test func customArtInBothThemes() async throws {
    let art: [(String, AppleIconArt)] = [
      ("Clipboard", IconArt.clipboard), ("Lyrics", IconArt.lyrics), ("High Alert", IconArt.highAlert),
      ("Text Capture", IconArt.textCapture), ("Teleprompter", IconArt.teleprompter), ("DropClip", IconArt.dropClip),
      ("Emoji", IconArt.emoji), ("Cleaner", IconArt.cleaner), ("Remove BG", IconArt.removeBackground),
      ("Agents", IconArt.agents), ("Island", IconArt.island), ("Upload", IconArt.upload),
      ("Transform", IconArt.transform), ("Droplets", IconArt.droplets), ("Connections", IconArt.connections),
      ("About", IconArt.about),
    ]
    for appearance in [IconAppearance.light, .dark] {
      let sheet = IconSheet(
        items: art.map { ($0.0, FeatureIcon.custom($0.1)) }, size: 64, columns: 8, dark: appearance == .dark,
        appearance: appearance)
      try await render(sheet, name: "icons-custom-\(appearance == .dark ? "dark" : "light").png")
    }
  }

  @Test func everyFeatureHasAnIcon() {
    // Real icons fall back to art, so every icon must have a symbol that exists.
    let icons = HomeWidget.allCases.map(\.icon) + IslandWidgetTile.allCases.map(\.icon) + SettingsPane.allCases.map(\.icon)
    for icon in icons {
      #expect(NSImage(systemSymbolName: icon.art.symbol, accessibilityDescription: nil) != nil, "\(icon.art.symbol)")
    }
  }

  @Test func iconThemeParsing() {
    #expect(IconAppearance.resolve(theme: "RegularDark", interfaceStyle: nil) == .dark)
    #expect(IconAppearance.resolve(theme: "ClearLight", interfaceStyle: "Dark") == .light)
    #expect(IconAppearance.resolve(theme: nil, interfaceStyle: "Dark") == .light)
    #expect(IconAppearance.resolve(theme: "RegularAutomatic", interfaceStyle: "Dark") == .dark)
  }

  // MARK: Helpers

  private func render<V: View>(_ view: V, name: String) async throws {
    let host = NSHostingView(rootView: view.fixedSize())
    let size = host.fittingSize
    host.frame = CGRect(origin: .zero, size: size)
    let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    defer { window.close() }
    host.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(200))
    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    let png = try #require(bitmap.representation(using: .png, properties: [:]))
    let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().appendingPathComponent(".renders")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try png.write(to: dir.appendingPathComponent(name))
  }
}

private struct IconSheet: View {
  let items: [(String, FeatureIcon)]
  let size: CGFloat
  let columns: Int
  let dark: Bool
  var appearance: IconAppearance = .current

  var body: some View {
    let cell = max(size + 34, 78)
    LazyVGrid(columns: Array(repeating: GridItem(.fixed(cell), spacing: 6), count: columns), spacing: 14) {
      ForEach(items.indices, id: \.self) { index in
        VStack(spacing: 8) {
          FeatureIconView(items[index].1, size: size, appearance: appearance)
          Text(items[index].0).font(.system(size: 10, weight: .medium)).lineLimit(1)
            .foregroundStyle(dark ? .white.opacity(0.85) : .black.opacity(0.8))
        }
        .frame(width: cell)
      }
    }
    .padding(22)
    .background(dark ? Color(white: 0.06) : Color(white: 0.95))
  }
}
