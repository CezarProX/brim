import AppKit
import SwiftUI
import Testing

@testable import Brim

/// Renders the Transform panel to PNGs in `.renders/` so the design can be inspected.
@MainActor
@Suite(.serialized)
struct TransformPanelRenderTests {
  private func isolated() -> AppSettings {
    AppSettings(defaults: UserDefaults(suiteName: "QS-Render-\(UUID().uuidString)")!)
  }

  private func renderURL(_ name: String) throws -> URL {
    var root = URL(fileURLWithPath: #filePath)
    while root.pathComponents.count > 1, !FileManager.default.fileExists(atPath: root.appendingPathComponent("Package.swift").path) {
      root.deleteLastPathComponent()
    }
    let folder = root.appendingPathComponent(".renders", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder.appendingPathComponent(name)
  }

  private func render<V: View>(_ view: V, size: CGSize, name: String) async throws -> NSBitmapImageRep {
    let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height).background(Color.black).preferredColorScheme(.dark))
    let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    defer { window.close() }
    host.frame = CGRect(origin: .zero, size: size)
    host.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(900))
    host.layoutSubtreeIfNeeded()
    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    if let png = bitmap.representation(using: .png, properties: [:]) { try png.write(to: renderURL(name)) }
    return bitmap
  }

  private let size = CGSize(width: 440, height: TransformPanelView.preferredHeight + 28)

  private func panel(_ model: TransformPanelModel) -> some View {
    TransformPanelView(model: model, close: {}).padding(.horizontal, 22).padding(.vertical, 14)
  }

  @Test func rendersTheConfigureStateForAnImage() async throws {
    let fixtures = try TransformFixtures()
    defer { fixtures.cleanup() }
    let model = TransformPanelModel(files: [try fixtures.image("Screenshot 2026-10-22.jpg", width: 1200, height: 900),
                                            try fixtures.image("IMG_0042.jpg", width: 800, height: 600)], settings: isolated())
    let bitmap = try await render(panel(model), size: size, name: "transform-configure.png")
    #expect(bitmap.pixelsWide > 0)
    model.select(.resize)
    _ = try await render(panel(model), size: size, name: "transform-resize.png")
  }

  @Test func rendersVideoOptionsAndResults() async throws {
    let fixtures = try TransformFixtures()
    defer { fixtures.cleanup() }
    let video = try await fixtures.video("Screen Recording.mp4")
    let model = TransformPanelModel(files: [video], settings: isolated())
    model.select(.makeGIF)
    _ = try await render(panel(model), size: size, name: "transform-gif.png")

    let images = [try fixtures.image("a.jpg"), try fixtures.image("b.jpg"), try fixtures.image("c.jpg")]
    let running = TransformPanelModel(files: images, settings: isolated())
    let outcome = TransformOutcome(outputs: [images[0]], bytesBefore: 4_200_000, bytesAfter: 680_000)
    running.setForPreview(phase: .running, rows: [
      .init(id: 0, sources: [images[0]], state: .done(outcome)),
      .init(id: 1, sources: [images[1]], state: .running(0.62)),
      .init(id: 2, sources: [images[2]], state: .waiting),
    ])
    _ = try await render(panel(running), size: size, name: "transform-running.png")

    running.setForPreview(phase: .finished, rows: [
      .init(id: 0, sources: [images[0]], state: .done(outcome)),
      .init(id: 1, sources: [images[1]], state: .done(TransformOutcome(outputs: [images[1]], bytesBefore: 2_100_000, bytesAfter: 410_000))),
      .init(id: 2, sources: [images[2]], state: .failed("Couldn’t read c.jpg.")),
    ])
    _ = try await render(panel(running), size: size, name: "transform-finished.png")
  }

  @Test func rendersTheQuickActionTiles() async throws {
    let row = QuickActionTilesRow(transform: { _ in }).frame(height: 84).padding(14)
    _ = try await render(row, size: CGSize(width: 420, height: 112), name: "quick-actions.png")
    let tray = BasketView(model: BasketModel(), registry: FloatingTrayRegistry(), number: 1, close: {})
    _ = try await render(tray.padding(20), size: CGSize(width: 320, height: 230), name: "floating-tray.png")
    for targets in [[DropTarget.keep, .convert, .airDrop], [.keep, .localSend, .airDrop, .convert]] {
      let size = FloatingTrayLayout.quickActionsSize(tileCount: targets.count)
      let panel = QuickActionsView(targets: targets, size: size) { _, _ in }.padding(24)
      _ = try await render(panel, size: CGSize(width: size.width + 48, height: size.height + 48),
                           name: "shake-actions-\(targets.count).png")
    }
  }
}
