import AppKit
import SwiftUI
import Testing
@testable import Brim

@MainActor
struct ClipboardPinboardRenderTests {
    @Test("Library renders smart pinboard tabs and filters by the selected one")
    func rendersPinboardTabs() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("QS-PB-\(UUID().uuidString)")
        let board = NSPasteboard(name: .init(UUID().uuidString))
        defer { try? FileManager.default.removeItem(at: directory); board.releaseGlobally() }
        let settings = AppSettings(defaults: UserDefaults(suiteName: "qs-render-\(UUID())")!)
        settings.clipboardPinboards = ClipboardPinboard.allCases.map(\.rawValue)
        let clipboard = ClipboardStore(directory: directory.appendingPathComponent("c"), pasteboard: board, settings: settings)
        clipboard.start()
        for value in ["func greet(name: String) -> String {\n    return \"Hi \\(name)\"\n}", "hello@example.com",
                      "https://example.com/post", "#3B82F6", "Pick up the parcel on Friday."] {
            board.clearContents()
            board.setString(value, forType: .string)
            await clipboard.captureChange()
        }
        clipboard.stop()
        let shelf = ShelfStore(directory: directory.appendingPathComponent("s"))
        let size = CGSize(width: 640, height: 250)
        let host = NSHostingView(rootView: ClipboardLibraryView(store: shelf, clipboard: clipboard, settings: settings)
            .padding(12).frame(width: size.width, height: size.height).background(.black).preferredColorScheme(.dark))
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        host.frame = CGRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(200))
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent(".renders")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try png.write(to: folder.appendingPathComponent("clipboard-pinboards.png"))
        #expect(png.count > 5_000)
        #expect(ClipboardPinboard.enabled(in: settings).count == 6)
    }
}
