import AppKit
import SwiftUI
import Testing

@testable import Brim

/// Renders the Island Tour's coach card to `.renders/` so it can be looked at, in English and Romanian.
@MainActor
@Suite(.serialized)
struct IslandTourRenderTests {
  private func card(_ step: IslandTourStep, _ context: IslandTourContext = IslandTourContext(hasTrack: true)) -> some View {
    let model = IslandTourCardModel()
    model.step = step
    model.context = context
    model.visible = true
    return IslandTourCard(model: model)
  }

  private var sheet: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .top, spacing: 0) {
        card(.open)
        card(.home)
        card(.music, IslandTourContext(hasTrack: false))
      }
      HStack(alignment: .top, spacing: 0) {
        card(.swipe)
        card(.rightClick)
        card(.closed)
      }
      HStack(alignment: .top, spacing: 0) {
        card(.tray, IslandTourContext(floating: true))
        card(.widgets)
        card(.done)
      }
    }
    .padding(20)
  }

  /// A mock open island with the real tab bar, the arrow on the Music tab, and the card under it,
  /// laid out with the same numbers the live tour uses.
  private func scene(pointing page: IslandPage, step: IslandTourStep) -> some View {
    let pages = IslandPageOrder.visible(trayCount: 0, current: page)
    let width: CGFloat = 700
    let island = CGSize(width: 556, height: 210)
    let capsuleWidth = CGFloat(pages.count) * IslandTourPointerGeometry.tabWidth
      + CGFloat(pages.count - 1) * IslandTourPointerGeometry.tabSpacing + 2 * IslandNavigationLayout.inset
    let capsule = CGRect(x: (width - capsuleWidth) / 2, y: island.height + IslandNavigationLayout.gap,
                         width: capsuleWidth, height: IslandNavigationLayout.height)
    let pointer = IslandTourPointerModel()
    if let centre = IslandTourPointerGeometry.tabCenter(page, pages: pages, trayCount: 0, capsule: capsule) {
      pointer.tip = CGPoint(x: centre.x, y: capsule.maxY + 3)
    }
    return ZStack(alignment: .topLeading) {
      UnevenRoundedRectangle(bottomLeadingRadius: 40, bottomTrailingRadius: 40, style: .continuous)
        .fill(Color.black)
        .frame(width: island.width, height: island.height)
        .offset(x: (width - island.width) / 2)
      IslandNavigationCapsule(page: page, pages: pages, select: { _ in }) { EmptyView() }
        .frame(width: capsule.width, height: capsule.height)
        .offset(x: capsule.minX, y: capsule.minY)
      IslandTourPointerView(model: pointer)
      card(step)
        .offset(x: (width - IslandTourCard.width) / 2 - IslandTourLayout.shadowMargin,
                y: capsule.maxY + IslandTourLayout.gap - IslandTourLayout.shadowMargin)
    }
    .frame(width: width, height: 560, alignment: .topLeading)
  }

  @Test(arguments: ["en", "ro"])
  func liveSceneRenders(language: String) async throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent()
    let saved = L10n.bundle
    defer { L10n.bundle = saved }
    L10n.bundle = try #require(Bundle(path: root.appendingPathComponent("Resources/\(language).lproj").path))
    let bitmap = try await render(scene(pointing: .music, step: .music), size: CGSize(width: 700, height: 560),
                                  name: "island-tour-live-\(language)")
    #expect(bright(bitmap) > 1_000, "the card, tab bar and arrow must draw")
  }

  @Test(arguments: ["en", "ro"])
  func coachCardRenders(language: String) async throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent()
    let saved = L10n.bundle
    defer { L10n.bundle = saved }
    L10n.bundle = try #require(Bundle(path: root.appendingPathComponent("Resources/\(language).lproj").path))
    let size = CGSize(width: 3 * (IslandTourCard.width + 2 * IslandTourLayout.shadowMargin) + 40, height: 690)
    let bitmap = try await render(sheet, size: size, name: "island-tour-card-\(language)")
    #expect(bright(bitmap) > 2_000, "the card's text and buttons must draw")
  }

  private func render<V: View>(_ view: V, size: CGSize, name: String) async throws -> NSBitmapImageRep {
    let backdrop = LinearGradient(colors: [Color(red: 0.16, green: 0.22, blue: 0.4), Color(red: 0.45, green: 0.2, blue: 0.35)],
                                  startPoint: .topLeading, endPoint: .bottomTrailing)
    let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height, alignment: .topLeading)
      .background(backdrop).preferredColorScheme(.dark))
    let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    defer { window.close() }
    host.frame = CGRect(origin: .zero, size: size)
    host.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(400))
    host.layoutSubtreeIfNeeded()
    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    let png = try #require(bitmap.representation(using: .png, properties: [:]))
    let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().appendingPathComponent(".renders")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try png.write(to: folder.appendingPathComponent("\(name).png"))
    return bitmap
  }

  private func bright(_ bitmap: NSBitmapImageRep) -> Int {
    var count = 0
    for y in stride(from: 0, to: bitmap.pixelsHigh, by: 2) {
      for x in stride(from: 0, to: bitmap.pixelsWide, by: 2) {
        if let c = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
           c.redComponent > 0.85, c.greenComponent > 0.85, c.blueComponent > 0.85 { count += 1 }
      }
    }
    return count
  }
}
