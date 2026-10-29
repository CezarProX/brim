import AppKit
import SwiftUI
import Testing
import Vision
@testable import Brim

@MainActor
struct ClipboardLibraryViewTests {
    @Test("Library renders searchable screenshot, image, text and link content")
    func libraryRendersSyntheticContent() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Brim-LibraryRender-\(UUID().uuidString)")
        let board = NSPasteboard(name: .init("Brim-LibraryRender-\(UUID().uuidString)"))
        defer { try? FileManager.default.removeItem(at: directory); board.releaseGlobally() }
        let shelf = ShelfStore(directory: directory.appendingPathComponent("shots"))
        let clipboard = ClipboardStore(directory: directory.appendingPathComponent("clipboard"), pasteboard: board)
        clipboard.start()
        defer { clipboard.stop() }
        let image = try fixture()
        shelf.add(image, id: UUID())
        for value in ["Meeting notes\nA synthetic note for the library.", "https://example.com/library"] {
            board.clearContents()
            board.setString(value, forType: .string)
            await clipboard.captureChange()
        }
        board.clearContents()
        board.setData(try ImageEncoder.pngDataPreservingAlpha(from: image), forType: .png)
        await clipboard.captureChange()
        clipboard.stop()
        #expect(clipboard.entries.map(\.kind) == [.image, .link, .text])
        #expect(shelf.entries.count == 1)

        let size = CGSize(width: 544, height: 270)
        let host = NSHostingView(rootView: ClipboardLibraryView(store: shelf, clipboard: clipboard)
            .frame(width: size.width, height: size.height).background(.black).preferredColorScheme(.dark))
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        host.frame = CGRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(180))
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let cgImage = try #require(bitmap.cgImage)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: cgImage).perform([request])
        let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ").lowercased()
        // Filters are icons now; the cards name each kind and show its content. The strip
        // scrolls sideways, so only the first three cards are fully on screen at this width.
        for label in ["clipboard", "image", "link", "text", "meeting notes", "example.com"] {
            #expect(text.contains(label), "Rendered library must visibly include \(label). OCR: \(text)")
        }
        var greenPixels = 0
        for y in stride(from: 90, to: 175, by: 2) {
            for x in stride(from: 10, to: 160, by: 2) {
                let scale = CGFloat(bitmap.pixelsWide) / size.width
                guard let color = bitmap.colorAt(x: Int(CGFloat(x) * scale), y: Int(CGFloat(y) * scale))?.usingColorSpace(.deviceRGB) else { continue }
                if color.greenComponent > 0.65 && color.greenComponent - color.redComponent > 0.25
                    && color.greenComponent - color.blueComponent > 0.3 { greenPixels += 1 }
            }
        }
        #expect(greenPixels > 500, "The copied image must appear in the first card")
        if let destination = ProcessInfo.processInfo.environment["BRIM_SNAPSHOT_DIR"], !destination.isEmpty {
            let target = URL(fileURLWithPath: destination, isDirectory: true)
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            let snapshot = NSImage(size: size)
            snapshot.addRepresentation(bitmap)
            try ImageEncoder.pngDataPreservingAlpha(from: snapshot).write(to: target.appendingPathComponent("library.png"))
        }
    }

    private func fixture() throws -> NSImage {
        let context = try #require(CGContext(data: nil, width: 320, height: 180, bitsPerComponent: 8,
                                            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.1, green: 0.9, blue: 0.1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 320, height: 180))
        return NSImage(cgImage: try #require(context.makeImage()), size: CGSize(width: 320, height: 180))
    }
}
