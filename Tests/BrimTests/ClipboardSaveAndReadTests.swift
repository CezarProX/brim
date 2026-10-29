import AppKit
import Testing
@testable import Brim

@MainActor
struct ClipboardSaveAndReadTests {
    private func directory() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
    private func board() -> NSPasteboard { NSPasteboard(name: .init(UUID().uuidString)) }
    private func copy(_ text: String, to pasteboard: NSPasteboard) {
        pasteboard.clearContents(); pasteboard.setString(text, forType: .string)
    }

    @Test func coalescesSavesAndFlushesOnDemand() async throws {
        let root = directory(), pasteboard = board()
        defer { try? FileManager.default.removeItem(at: root); pasteboard.releaseGlobally() }
        let store = ClipboardStore(directory: root, pasteboard: pasteboard, saveDelay: 30)
        store.start()
        defer { store.stop() }
        let baseline = store.saveCount
        for text in ["one", "two", "three"] {
            copy(text, to: pasteboard)
            await store.captureChange()
        }
        #expect(store.entries.count == 3)
        #expect(store.saveCount == baseline)
        #expect(ClipboardStore(directory: root, pasteboard: pasteboard).entries.isEmpty)
        store.flushPendingSave()
        #expect(store.saveCount == baseline + 1)
        #expect(ClipboardStore(directory: root, pasteboard: pasteboard).entries == store.entries)
        store.flushPendingSave()
        #expect(store.saveCount == baseline + 1)
    }

    @Test func writesOnceAfterTheDelay() async throws {
        let root = directory(), pasteboard = board()
        defer { try? FileManager.default.removeItem(at: root); pasteboard.releaseGlobally() }
        let store = ClipboardStore(directory: root, pasteboard: pasteboard, saveDelay: 0.2)
        store.start()
        defer { store.stop() }
        let baseline = store.saveCount
        for text in ["a", "b"] { copy(text, to: pasteboard); await store.captureChange() }
        #expect(store.saveCount == baseline)
        try await Task.sleep(for: .milliseconds(600))
        #expect(store.saveCount == baseline + 1)
        #expect(ClipboardStore(directory: root, pasteboard: pasteboard).entries.count == 2)
    }

    @Test func stopFlushesPendingHistory() async throws {
        let root = directory(), pasteboard = board()
        defer { try? FileManager.default.removeItem(at: root); pasteboard.releaseGlobally() }
        let store = ClipboardStore(directory: root, pasteboard: pasteboard, saveDelay: 30)
        store.start()
        copy("keep me", to: pasteboard)
        await store.captureChange()
        store.stop()
        #expect(ClipboardStore(directory: root, pasteboard: pasteboard).entries.map(\.text) == ["keep me"])
    }

    @Test func slowSourceTimesOutWithoutBlockingTheMainActor() async throws {
        let root = directory(), pasteboard = board()
        defer { try? FileManager.default.removeItem(at: root); pasteboard.releaseGlobally() }
        let store = ClipboardStore(
            directory: root, pasteboard: pasteboard, readTimeout: 0.2,
            readSnapshot: { _ in Thread.sleep(forTimeInterval: 1.5); return .text("too late") })
        store.start()
        defer { store.stop() }
        copy("slow", to: pasteboard)
        let began = Date()
        await store.captureChange()
        #expect(Date().timeIntervalSince(began) < 1.0)
        #expect(store.entries.isEmpty)
        // The monitor is free again for the next copy.
        #expect(store.isMonitoring)
    }

    @Test func readerBoundsTextAndReadsOffMain() async throws {
        let pasteboard = board()
        defer { pasteboard.releaseGlobally() }
        let reader = ClipboardSnapshotReader(maxImageBytes: 1024, maxTextBytes: 8)
        let box = ClipboardPasteboardBox(pasteboard: pasteboard)
        copy("short", to: pasteboard)
        let ok = await ClipboardSnapshotReader.run(timeout: 2) { reader.read(box) }
        #expect(ok == .text("short"))
        copy("this is far too long", to: pasteboard)
        let big = await ClipboardSnapshotReader.run(timeout: 2) { reader.read(box) }
        #expect(big == nil)
    }
}
