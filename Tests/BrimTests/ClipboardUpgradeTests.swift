import AppKit
import Foundation
import Testing

@testable import Brim

@MainActor
@Suite(.serialized)
struct ClipboardUpgradeTests {
  private func directory() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  }
  private func board() -> NSPasteboard { NSPasteboard(name: .init(UUID().uuidString)) }

  @Test func recognizesColorCodes() {
    #expect(ClipboardEntry.color(from: "#007AFF") != nil)
    #expect(ClipboardEntry.color(from: " f34b38 ") != nil)
    #expect(ClipboardEntry.color(from: "#fff") != nil)
    #expect(ClipboardEntry.color(from: "rgb(255, 128, 0)") != nil)
    #expect(ClipboardEntry.color(from: "meeting at 3pm") == nil)
    #expect(ClipboardEntry.color(from: "#GGGGGG") == nil)
    #expect(ClipboardEntry.color(from: "rgb(300, 0, 0)") == nil)
  }

  @Test func capturesColorsFilesAndTheSourceApp() async throws {
    let pasteboard = board()
    let store = ClipboardStore(
      directory: directory(), pasteboard: pasteboard, frontmostApp: { "com.figma.Desktop" })
    store.start()
    defer { store.stop() }

    pasteboard.clearContents()
    pasteboard.setString("#007AFF", forType: .string)
    await store.captureChange()
    #expect(store.entries.first?.kind == .color)
    #expect(store.entries.first?.sourceApp == "com.figma.Desktop")

    let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).txt")
    try Data("x".utf8).write(to: file)
    defer { try? FileManager.default.removeItem(at: file) }
    pasteboard.clearContents()
    pasteboard.writeObjects([file as NSURL])
    await store.captureChange()
    let entry = try #require(store.entries.first)
    #expect(entry.kind == .file)
    #expect(entry.fileURLs == [file.standardizedFileURL])

    #expect(store.copy(entry))
    let copied = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL]
    #expect(copied?.first?.standardizedFileURL == file.standardizedFileURL)
  }

  @Test func tagsBlurAndEditsPersist() async throws {
    let folder = directory()
    let pasteboard = board()
    let store = ClipboardStore(directory: folder, pasteboard: pasteboard)
    store.start()
    pasteboard.clearContents()
    pasteboard.setString("meeting at 3", forType: .string)
    await store.captureChange()
    store.stop()
    let entry = try #require(store.entries.first)
    #expect(store.setTag(entry, .work))
    #expect(store.setBlurred(try #require(store.entries.first), true))
    #expect(store.edit(try #require(store.entries.first), text: "meeting at 5pm"))

    let reloaded = ClipboardStore(directory: folder, pasteboard: board())
    let restored = try #require(reloaded.entries.first)
    #expect(restored.tag == .work)
    #expect(restored.isBlurred)
    #expect(restored.text == "meeting at 5pm")
    #expect(restored.id == entry.id)
  }

  @Test func copyingTheSameContentAgainCountsIt() async throws {
    let pasteboard = board()
    let store = ClipboardStore(directory: directory(), pasteboard: pasteboard)
    store.start()
    defer { store.stop() }
    for text in ["hello", "other", "hello"] {
      pasteboard.clearContents()
      pasteboard.setString(text, forType: .string)
      await store.captureChange()
    }
    #expect(store.entries.first?.text == "hello")
    #expect(store.entries.first?.copies == 2)
    #expect(store.entries.last?.copies == 1)
  }
}
