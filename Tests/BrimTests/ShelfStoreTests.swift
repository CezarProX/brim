import AppKit
import Testing
@testable import Brim

@MainActor
struct ShelfStoreTests {
    private func image(_ width: Int = 16) throws -> NSImage {
        let context = try #require(CGContext(data: nil, width: width, height: 12,
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(NSColor.red.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: 12))
        return NSImage(cgImage: try #require(context.makeImage()), size: .zero)
    }

    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    @Test func persistsImagesAndReplacesCaptureWithoutDuplicates() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ShelfStore(directory: root)
        let first = UUID(), second = UUID()
        store.add(try image(), id: first)
        store.add(try image(), id: second)
        store.add(try image(24), id: first)
        #expect(store.entries.map(\.id) == [first, second])
        let reopened = ShelfStore(directory: root)
        #expect(reopened.entries == store.entries)
        let entry = try #require(reopened.entries.first)
        #expect(entry.pixelSize == "24x12")
        #expect(reopened.image(for: entry) != nil)
        #expect(reopened.thumbnail(for: entry) != nil)
        #expect(reopened.errorMessage == nil)
    }

    /// An unreadable index must not cost the user their screenshots on the next capture.
    @Test func unreadableIndexKeepsTheScreenshots() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ShelfStore(directory: root)
        let kept = UUID()
        store.add(try image(), id: kept)
        let keptURL = store.fileURL(for: try #require(store.entries.first))
        let index = try #require(try FileManager.default.contentsOfDirectory(atPath: root.path).first { $0.hasSuffix(".json") })
        try Data("{ not json".utf8).write(to: root.appendingPathComponent(index))
        let reopened = ShelfStore(directory: root)
        #expect(reopened.entries.map(\.id) == [kept])
        reopened.add(try image(), id: UUID())
        #expect(FileManager.default.fileExists(atPath: keptURL.path))
        #expect(reopened.entries.count == 2)
    }

    @Test func evictsOldImagesAndOnlyClearsOwnedFiles() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ShelfStore(directory: root, maxCount: 2)
        store.add(try image(), id: UUID())
        let oldURL = store.fileURL(for: try #require(store.entries.first))
        store.add(try image(), id: UUID())
        store.add(try image(), id: UUID())
        #expect(store.entries.count == 2)
        #expect(!FileManager.default.fileExists(atPath: oldURL.path))
        let unrelated = root.appendingPathComponent("keep.txt")
        try Data("keep".utf8).write(to: unrelated)
        store.remove(try #require(store.entries.first))
        #expect(store.entries.count == 1)
        store.clear()
        #expect(store.entries.isEmpty)
        #expect(ShelfStore(directory: root).entries.isEmpty)
        #expect(FileManager.default.fileExists(atPath: unrelated.path))
    }

    @Test func rejectsOversizedCaptureAndReportsFailure() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ShelfStore(directory: root, maxBytes: 1)
        store.add(try image(), id: UUID())
        #expect(store.entries.isEmpty)
        #expect(store.errorMessage != nil)
    }

    @Test func byteBudgetEvictsOlderCaptures() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try image()
        let initial = ShelfStore(directory: root)
        initial.add(source, id: UUID())
        let entry = try #require(initial.entries.first)
        let urls = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        let bytes = try urls.filter { $0.pathExtension == "png" }.reduce(0) {
            try $0 + Data(contentsOf: $1).count
        }
        let limited = ShelfStore(directory: root, maxBytes: bytes + 1)
        let newest = UUID()
        limited.add(source, id: newest)
        #expect(limited.entries.map(\.id) == [newest])
        #expect(!FileManager.default.fileExists(atPath: initial.fileURL(for: entry).path))
    }

    @Test func failedMetadataWritePreservesExistingCapture() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ShelfStore(directory: root)
        let id = UUID()
        store.add(try image(), id: id)
        let original = try #require(store.entries.first)
        let originalData = try Data(contentsOf: store.fileURL(for: original))
        let metadata = root.appendingPathComponent("entries.json")
        try FileManager.default.removeItem(at: metadata)
        try FileManager.default.createDirectory(at: metadata, withIntermediateDirectories: false)
        store.add(try image(24), id: id)
        #expect(store.entries == [original])
        #expect(try Data(contentsOf: store.fileURL(for: original)) == originalData)
        #expect(store.errorMessage != nil)
        store.clear()
        #expect(store.entries == [original])
    }

    @Test func cleansOrphansAndReportsMissingImages() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ShelfStore(directory: root)
        store.add(try image(), id: UUID())
        let entry = try #require(store.entries.first)
        #expect(store.thumbnail(for: entry) != nil)
        #expect(store.thumbnail(for: entry) != nil)
        try FileManager.default.removeItem(at: store.fileURL(for: entry))
        #expect(store.image(for: entry) == nil)
        #expect(store.errorMessage != nil)
        let reopened = ShelfStore(directory: root)
        #expect(reopened.entries.isEmpty)
        #expect(reopened.thumbnail(for: entry) == nil)
        let permissions = try FileManager.default.attributesOfItem(atPath: root.path)
        #expect((permissions[.posixPermissions] as? NSNumber)?.intValue == 0o700)
    }

    @Test func reportsInvalidStorageAndCorruptMetadata() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data().write(to: root)
        let invalid = ShelfStore(directory: root)
        invalid.add(try image(), id: UUID())
        #expect(invalid.entries.isEmpty)
        #expect(invalid.errorMessage != nil)
        try FileManager.default.removeItem(at: root)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("broken".utf8).write(to: root.appendingPathComponent("entries.json"))
        let corrupt = ShelfStore(directory: root)
        #expect(corrupt.entries.isEmpty)
        #expect(corrupt.errorMessage != nil)
    }
}
