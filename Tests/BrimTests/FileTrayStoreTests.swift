import AppKit
import Foundation
import Testing

@testable import Brim

@MainActor
@Suite(.serialized)
struct FileTrayStoreTests {
  private let root: URL
  private let storage: URL

  init() throws {
    root = FileManager.default.temporaryDirectory
      .appendingPathComponent("Brim-Tray-\(UUID().uuidString)", isDirectory: true)
    storage = root.appendingPathComponent("storage", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  }

  private func file(_ name: String, contents: String = "hello") throws -> URL {
    let url = root.appendingPathComponent(name)
    try Data(contents.utf8).write(to: url)
    return url
  }

  private func image(_ name: String) throws -> URL {
    let url = root.appendingPathComponent(name)
    let image = NSImage(size: NSSize(width: 8, height: 8))
    image.lockFocus()
    NSColor.systemRed.setFill()
    NSRect(x: 0, y: 0, width: 8, height: 8).fill()
    image.unlockFocus()
    try ImageEncoder.pngDataPreservingAlpha(from: image).write(to: url)
    return url
  }

  @Test func addsExistingFilesOnceAndPersists() throws {
    defer { try? FileManager.default.removeItem(at: root) }
    let store = FileTrayStore(directory: storage, flashes: nil)
    let a = try file("a.txt")
    let b = try file("b.txt")
    let missing = root.appendingPathComponent("missing.txt")
    #expect(store.add([a, b, missing, a]) == 2)
    #expect(store.add([a]) == 0)
    #expect(store.items.count == 2)
    #expect(store.totalBytes() == 10)

    let reloaded = FileTrayStore(directory: storage, flashes: nil)
    #expect(Set(reloaded.items.map { reloaded.url(for: $0).lastPathComponent }) == ["a.txt", "b.txt"])
    reloaded.remove([reloaded.items[0].id])
    #expect(reloaded.items.count == 1)
  }

  @Test func followsARenamedFileThroughItsBookmark() throws {
    defer { try? FileManager.default.removeItem(at: root) }
    let store = FileTrayStore(directory: storage, flashes: nil)
    store.add([try file("draft.txt")])
    let item = try #require(store.items.first)
    store.rename(item, to: "final.txt")
    #expect(store.url(for: try #require(store.items.first)).lastPathComponent == "final.txt")
    store.rename(try #require(store.items.first), to: "../escape.txt")
    #expect(store.url(for: try #require(store.items.first)).lastPathComponent == "final.txt")
  }

  @Test func uniqueNamesNeverOverwrite() throws {
    defer { try? FileManager.default.removeItem(at: root) }
    _ = try file("Archive.zip")
    let next = FileTrayStore.uniqueURL(in: root, name: "Archive", fileExtension: "zip")
    #expect(next.lastPathComponent == "Archive 2.zip")
  }

  @Test func convertsImagesBesideTheOriginal() async throws {
    defer { try? FileManager.default.removeItem(at: root) }
    let store = FileTrayStore(directory: storage, flashes: nil)
    store.add([try image("shot.png"), try file("notes.txt")])
    await store.convert(store.items, to: .jpeg)
    #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("shot.jpeg").path)
      || FileManager.default.fileExists(atPath: root.appendingPathComponent("shot.jpg").path))
    #expect(store.items.count == 3)
  }

  @Test func zipsTheSelectionIntoTheTray() async throws {
    defer { try? FileManager.default.removeItem(at: root) }
    let store = FileTrayStore(directory: storage, flashes: nil)
    store.add([try file("one.txt"), try file("two.txt")])
    await store.zip(store.items)
    let archive = root.appendingPathComponent("Archive.zip")
    #expect(FileManager.default.fileExists(atPath: archive.path))
    #expect(store.items.contains { store.url(for: $0).lastPathComponent == "Archive.zip" })
  }
}
