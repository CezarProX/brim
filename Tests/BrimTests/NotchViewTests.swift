import AppKit
import SwiftUI
import Testing
@testable import Brim

@MainActor
@Suite(.serialized)
struct NotchViewTests {
    @Test("Collapsed notch has no colored indicator or pixels below the hardware")
    func collapsedNotchIsInvisibleBelowHardware() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Brim-CollapsedTest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let presentation = NotchPresentation()
        presentation.geometry = NotchGeometry(
            screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982), notchWidth: 184, notchHeight: 32
        )
        let size = presentation.geometry.expandedSize
        let host = NSHostingView(rootView: NotchShelfView(presentation: presentation, store: ShelfStore(directory: directory)))
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.isOpaque = false
        defer { window.close() }
        window.contentView = host
        host.frame = CGRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let scale = CGFloat(bitmap.pixelsHigh) / size.height
        var coloredPixels = 0
        var belowNotchPixels = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: 2) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                      color.alphaComponent > 0.1 else { continue }
                if color.redComponent > 0.1 || color.greenComponent > 0.1 || color.blueComponent > 0.1 {
                    coloredPixels += 1
                }
                if CGFloat(y) > 33 * scale { belowNotchPixels += 1 }
            }
        }
        #expect(coloredPixels == 0, "Retracted notch must contain no colored line")
        #expect(belowNotchPixels == 0, "Retracted notch must not extend below the hardware")
        let image = NSImage(size: size)
        image.addRepresentation(bitmap)
        try saveSnapshot(image, name: "collapsed")
    }

    @Test("Expanded shelf renders empty and populated states", arguments: [false, true])
    func expandedShelfRenders(populated: Bool) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Brim-ViewTest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ShelfStore(directory: directory)
        if populated {
            store.add(try fixture(color: .systemIndigo), id: UUID())
            store.add(try fixture(color: .systemTeal), id: UUID())
            store.add(try fixture(color: .systemOrange), id: UUID())
            #expect(store.entries.count == 3)
            #expect(store.errorMessage == nil)
        }

        let presentation = NotchPresentation()
        presentation.geometry = NotchGeometry(
            screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            notchWidth: 184, notchHeight: 32
        )
        presentation.isExpanded = true
        let size = presentation.geometry.expandedSize
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.isOpaque = false
        defer { window.close() }
        // The fresh-install Home (Media and Captures, both medium), not the user's saved layout.
        let home = HomeWidgetStore(widgets: [.media, .captures], persist: { _ in })
        let host = NSHostingView(rootView: NotchShelfView(presentation: presentation, store: store, homeWidgets: home))
        window.contentView = host
        host.frame = CGRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        // Let SwiftUI install its AppKit-backed scroll and menu views without showing a window.
        try await Task.sleep(for: .milliseconds(150))
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let image = NSImage(size: size)
        image.addRepresentation(bitmap)
        #expect(bitmap.pixelsWide > 0)
        #expect(bitmap.pixelsHigh > 0)
        if populated {
            // Colored card interiors must actually appear; a nonempty image alone isn't enough.
            var orangePixels = 0
            var tealPixels = 0
            for y in stride(from: 0, to: bitmap.pixelsHigh, by: 3) {
                for x in stride(from: 0, to: bitmap.pixelsWide, by: 3) {
                    guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                    if color.redComponent > 0.8 && color.greenComponent > 0.2
                        && color.greenComponent < 0.85 && color.blueComponent < 0.5
                        && color.redComponent > color.greenComponent + 0.15 { orangePixels += 1 }
                    if color.redComponent < 0.5 && color.greenComponent > 0.5
                        && color.blueComponent > 0.5 { tealPixels += 1 }
                }
            }
            // Sampled every third pixel, so 60 hits is still a solid patch of the card; the thumbnails got
            // smaller when Home began sharing its row with more widgets, which left this sitting on 100.
            #expect(orangePixels > 60, "The orange screenshot card must be visible")
            #expect(tealPixels > 60, "The teal screenshot card must be visible")
        }
        if !populated {
            var textPixels = 0
            let middle = (bitmap.pixelsHigh / 4)..<(bitmap.pixelsHigh * 2 / 3)
            for y in middle {
                for x in stride(from: bitmap.pixelsWide / 5, to: bitmap.pixelsWide * 4 / 5, by: 2) {
                    guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                    if color.redComponent > 0.7 && color.greenComponent > 0.7
                        && color.blueComponent > 0.7 { textPixels += 1 }
                }
            }
            #expect(textPixels > 100, "The quiet Home message must appear in the shelf body")
        }
        try saveSnapshot(image, name: populated ? "populated" : "empty")
    }

    @Test("Shelf editor export preserves Retina pixels and applies annotations")
    func editorExportPreservesPixels() throws {
        let source = try fixture(color: .systemIndigo)
        let session = EditorSession()
        session.addAnnotation(Annotation(
            tool: .rectangle,
            rect: CGRect(x: 30, y: 30, width: 90, height: 60),
            style: AnnotationStyle(color: .white, lineWidth: 6)
        ))
        let rendered = session.render(over: source, canvasSize: source.size)
        let dimensions = ImageEncoder.pixelSize(of: rendered)
        #expect(dimensions == CGSize(width: 640, height: 360))
        #expect(rendered.size == CGSize(width: 320, height: 180))
        #expect(try ImageEncoder.pngDataPreservingAlpha(from: rendered)
                != ImageEncoder.pngDataPreservingAlpha(from: source))
    }

    /// Synthetic artwork only: no screen recording, clipboard, or user files.
    private func fixture(color: NSColor) throws -> NSImage {
        let context = try #require(CGContext(
            data: nil, width: 640, height: 360, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(color.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 640, height: 360))
        context.setFillColor(NSColor.white.withAlphaComponent(0.2).cgColor)
        context.fill(CGRect(x: 40, y: 50, width: 250, height: 250))
        context.fill(CGRect(x: 320, y: 230, width: 270, height: 30))
        context.fill(CGRect(x: 320, y: 170, width: 180, height: 20))
        return NSImage(cgImage: try #require(context.makeImage()), size: CGSize(width: 320, height: 180))
    }

    private func saveSnapshot(_ image: NSImage, name: String) throws {
        guard let destination = ProcessInfo.processInfo.environment["BRIM_SNAPSHOT_DIR"],
              !destination.isEmpty else { return }
        let directory = URL(fileURLWithPath: destination, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try ImageEncoder.pngDataPreservingAlpha(from: image)
            .write(to: directory.appendingPathComponent("\(name).png"), options: .atomic)
    }
}
