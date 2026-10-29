import AppKit
import SwiftUI
import Testing

@testable import Brim

/// Renders the changed views to `.renders/` so they can be looked at.
@MainActor
@Suite(.serialized)
struct TrayClipboardGapRenderTests {
  private func render<V: View>(_ view: V, size: CGSize, name: String, wait: Duration = .milliseconds(250)) async throws {
    let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height).background(.black).preferredColorScheme(.dark))
    let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    defer { window.close() }
    host.frame = CGRect(origin: .zero, size: size)
    host.layoutSubtreeIfNeeded()
    try await Task.sleep(for: wait)
    host.layoutSubtreeIfNeeded()
    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    let png = try #require(bitmap.representation(using: .png, properties: [:]))
    let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().appendingPathComponent(".renders")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try png.write(to: folder.appendingPathComponent("\(name).png"))
  }

  @Test func clipboardLibraryShowsSelectionOrderAndCursor() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("QS-GapLib-\(UUID().uuidString)")
    let board = NSPasteboard(name: .init("QS-GapLib-\(UUID().uuidString)"))
    defer { try? FileManager.default.removeItem(at: directory); board.releaseGlobally() }
    let shelf = ShelfStore(directory: directory.appendingPathComponent("shots"))
    let clipboard = ClipboardStore(directory: directory.appendingPathComponent("clipboard"), pasteboard: board)
    clipboard.start()
    defer { clipboard.stop() }
    for value in ["Meeting notes\nSecond line of a note.", "https://example.com/library", "let answer = 42"] {
      board.clearContents(); board.setString(value, forType: .string)
      await clipboard.captureChange()
    }
    clipboard.stop()
    let ids = clipboard.entries.map { "clipboard-\($0.id)" }
    // Newest first: pick the oldest then the newest, so the badges read 1 and 2 out of display order.
    let picked = [ids[2], ids[0]]
    try await render(
      ClipboardLibraryView(store: shelf, clipboard: clipboard, preselected: picked),
      size: CGSize(width: 544, height: 270), name: "gap-clipboard-selection")
    #expect(clipboard.entries.count == 3)
  }

  @Test func fileTrayShowsPinBadge() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("QS-GapTray-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    var urls: [URL] = []
    for name in ["Report.pdf", "Photo.png", "Notes.txt"] {
      let url = folder.appendingPathComponent(name)
      try Data("x".utf8).write(to: url)
      urls.append(url)
    }
    let store = FileTrayStore(directory: folder.appendingPathComponent("tray"))
    store.add(urls)
    store.togglePin([store.items.last!.id])
    try await render(FileTrayView(store: store), size: CGSize(width: 560, height: 200), name: "gap-file-tray-pinned")
  }

  @Test func fileTrayShowsScreenshotsAsCards() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("QS-TrayCards-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    var urls: [URL] = []
    for (index, color) in [NSColor.systemTeal, .systemOrange, .systemPurple].enumerated() {
      let image = NSImage(size: CGSize(width: 1600, height: 500), flipped: false) { rect in
        color.setFill()
        rect.fill()
        NSColor.white.setFill()
        CGRect(x: 80, y: 120, width: 700, height: 70).fill()
        return true
      }
      let url = folder.appendingPathComponent("Screenshot 2026-10-27 at 17.4\(index).05.png")
      try ImageEncoder.pngDataPreservingAlpha(from: image).write(to: url)
      urls.append(url)
    }
    let notes = folder.appendingPathComponent("Notes.txt")
    try Data("x".utf8).write(to: notes)
    let store = FileTrayStore(directory: folder.appendingPathComponent("tray"))
    store.add(urls + [notes])
    try await render(
      FileTrayView(store: store, selection: [store.items[1].id]), size: CGSize(width: 560, height: 200),
      name: "file-tray-cards", wait: .milliseconds(900))
  }

  @Test func traySettingsSectionRenders() async throws {
    try await render(
      ScrollView { TrayExtrasSettingsSection().padding(16) }.environment(\.colorScheme, .light).background(Color(white: 0.95)),
      size: CGSize(width: 560, height: 760), name: "gap-tray-settings", wait: .milliseconds(400))
  }
}
