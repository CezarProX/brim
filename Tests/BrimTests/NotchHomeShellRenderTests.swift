import AppKit
import SwiftUI
import Testing

@testable import Brim

/// The whole open island at Home, through `NotchShelfView`, on a 1512×982 notched Mac and on the pill.
/// Over a pure green backdrop the island is everything that is not green; a widget card cut by the
/// island's edge would put lit card pixels right against the green. The check walks every pixel row
/// through the cards and requires a dark margin between the island's edge and the first and last
/// card pixel on both sides.
@MainActor
@Suite(.serialized)
struct NotchHomeShellRenderTests {
  enum Style: String, CaseIterable { case pill, notch }

  private static let output = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().appendingPathComponent(".renders/home-renders", isDirectory: true)
  private let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
  private let canvas = CGSize(width: 740, height: 330)

  private func geometry(_ style: Style) -> NotchGeometry {
    style == .notch
      ? NotchGeometry(screenFrame: screen, notchWidth: 184, notchHeight: 32)
      : NotchGeometry.dynamicIsland(screenFrame: screen)
  }

  private func s(_ widget: HomeWidget) -> HomeWidgetItem { HomeWidgetItem(widget, .small) }
  private func m(_ widget: HomeWidget) -> HomeWidgetItem { HomeWidgetItem(widget, .medium) }

  private func render(_ items: [HomeWidgetItem], style: Style, editing: Bool = false, name: String) async throws
    -> (NSBitmapImageRep, HomeWidgetStore, NotchGeometry)
  {
    let layout = HomeWidgetStore(items: items, persist: { _ in }, scrollMode: { .automatic })
    layout.isEditing = editing
    let presentation = NotchPresentation()
    presentation.navigate(to: .showing(.home))
    presentation.homeTapped = true
    let geo = geometry(style)
    presentation.geometry = geo
    presentation.isExpanded = true
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let prefs = AppSettings(defaults: UserDefaults(suiteName: "qs-home-shell-\(UUID().uuidString)")!)
    let view = NotchShelfView(
      presentation: presentation, store: ShelfStore(directory: directory),
      nowPlaying: NowPlayingModel(enabledSources: []), homeWidgets: layout,
      notifications: NotificationHUDModel(settings: prefs), glances: IslandGlanceModel(settings: prefs),
      theme: IslandTheme(surface: .black),
      playingNext: PlayingNextModel(read: { _ in "" }, perform: { _ in "" }, fetchArtwork: { _ in nil }))
    let host = NSHostingView(
      rootView: view.padding(.top, geo.topInset).frame(width: canvas.width, height: canvas.height, alignment: .top)
        .background(Color(red: 0, green: 1, blue: 0)))
    let window = NSWindow(contentRect: CGRect(origin: .zero, size: canvas), styleMask: [.borderless],
                          backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    defer { window.close() }
    host.frame = CGRect(origin: .zero, size: canvas)
    host.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(1200))
    host.layoutSubtreeIfNeeded()
    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    try? FileManager.default.createDirectory(at: Self.output, withIntermediateDirectories: true)
    if let png = bitmap.representation(using: .png, properties: [:]) {
      try png.write(to: Self.output.appendingPathComponent("shell-\(name)-\(style.rawValue).png"))
    }
    return (bitmap, layout, geo)
  }

  private func isGreen(_ c: NSColor) -> Bool { c.greenComponent > 0.8 && c.redComponent < 0.7 && c.blueComponent < 0.6 }
  private func isDark(_ c: NSColor) -> Bool { c.redComponent + c.greenComponent + c.blueComponent < 0.12 }

  /// Checks every pixel row through the widget row: the island spans the expected width, and lit
  /// card pixels never reach within `margin` points of its left or right edge.
  private func expectCardsInside(_ bitmap: NSBitmapImageRep, layout: HomeWidgetStore, geometry: NotchGeometry,
                                 name: String) {
    let scale = CGFloat(bitmap.pixelsWide) / canvas.width
    let band = geometry.isFloating ? 18 : max(geometry.notchHeight, 12) + HomeWidgetStore.topPadding
    let rowTop = geometry.topInset + band + (layout.isEditing ? HomeWidgetStore.editMargin : 0)
    // Skip the cards' own rounded corners at the top and bottom of the row.
    let rows = stride(from: rowTop + 24, to: rowTop + HomeWidgetStore.rowHeight - 24, by: 4)
    // Below its top shoulders the notch shape is inset by them, so on both styles the visible body is
    // exactly the shelf: the grid plus its side padding.
    let expectedWidth = layout.shelfWidth
    let margin: CGFloat = 12
    var lit = 0
    for y in rows {
      let py = Int(y * scale)
      var pixels: [NSColor] = []
      for px in 0..<bitmap.pixelsWide {
        pixels.append(bitmap.colorAt(x: px, y: py)?.usingColorSpace(.deviceRGB) ?? .black)
      }
      guard let left = pixels.firstIndex(where: { !isGreen($0) }),
        let right = pixels.lastIndex(where: { !isGreen($0) })
      else {
        Issue.record("\(name): no island on row \(y)")
        return
      }
      let width = CGFloat(right - left + 1) / scale
      #expect(abs(width - expectedWidth) <= 3, "\(name): island \(width) wide, grid asks \(expectedWidth)")
      let inset = Int(margin * scale)
      // The outermost pixels blend the shape's antialiased edge with the backdrop; start inside them.
      let blend = Int(2 * scale)
      let leftEdge = pixels[(left + blend)..<min(right, left + inset)]
      let rightEdge = pixels[max(left, right - inset + 1)...(right - blend)]
      #expect(leftEdge.allSatisfy(isDark), "\(name): a card touches the island's left edge on row \(y)")
      #expect(rightEdge.allSatisfy(isDark), "\(name): a card touches the island's right edge on row \(y)")
      lit += pixels[left...right].filter { !isDark($0) }.count
    }
    #expect(lit > 2_000, "\(name): the cards did not draw")
  }

  @Test(arguments: Style.allCases) func defaultHomeFitsTheIsland(style: Style) async throws {
    let (bitmap, layout, geo) = try await render([m(.media), s(.clock), s(.timer)], style: style, name: "home-default")
    expectCardsInside(bitmap, layout: layout, geometry: geo, name: "default \(style)")
  }

  /// The layout from the user's screenshot (Media, Batteries, Timer) — the outer cards used to be cut.
  @Test(arguments: Style.allCases) func screenshotLayoutFitsTheIsland(style: Style) async throws {
    let (bitmap, layout, geo) = try await render(
      [m(.media), m(.batteries), s(.timer)], style: style, name: "home-media-batteries-timer")
    #expect(layout.pages.count == 2)
    expectCardsInside(bitmap, layout: layout, geometry: geo, name: "screenshot \(style)")
  }

  @Test(arguments: Style.allCases) func allSmallFitsTheIsland(style: Style) async throws {
    let (bitmap, layout, geo) = try await render(
      [s(.clock), s(.timer), s(.agenda), s(.batteries)], style: style, name: "home-all-small")
    expectCardsInside(bitmap, layout: layout, geometry: geo, name: "all-small \(style)")
  }

  @Test(arguments: Style.allCases) func editingFitsTheIsland(style: Style) async throws {
    let (bitmap, layout, geo) = try await render(
      [m(.media), s(.clock), s(.timer)], style: style, editing: true, name: "home-editing")
    expectCardsInside(bitmap, layout: layout, geometry: geo, name: "editing \(style)")
  }
}
