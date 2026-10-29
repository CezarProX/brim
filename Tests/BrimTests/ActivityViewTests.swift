import AppKit
import SwiftUI
import Testing
import Vision
@testable import Brim

/// Render tests use isolated models and synthetic metadata. They never connect to a player or call app.
@MainActor
@Suite(.serialized)
struct ActivityViewTests {
    @Test("Opening the output drawer does not shrink or move its button before the shell grows")
    func outputButtonRemainsAnchoredDuringDrawerExpansion() async throws {
        let value = NowPlayingSnapshot(source: .music, title: "Fixture", artist: "Artist", album: "Album",
                                       duration: 240, position: 80, isPlaying: false)
        let model = NowPlayingModel(provider: RenderMusicProvider(value: value), enabledSources: [.music])
        await model.refreshNow()
        let outputs = AudioOutputModel(provider: RenderAudioOutputProvider())
        await outputs.refreshNow()
        // The shell initially still proposes the closed height when the drawer is toggled.
        let closed = try await render(NowPlayingView(model: model, outputs: outputs), name: "output-button-closed", height: 304)
        let opening = try await render(NowPlayingView(model: model, outputs: outputs, showingOutputs: true),
                                       name: "output-button-opening", height: 304)
        let iconArea = CGRect(x: 485, y: 180, width: 50, height: 45)
        let closedPixels = brightPixels(closed, in: iconArea)
        #expect(closedPixels > 50)
        #expect(brightPixels(opening, in: iconArea) >= closedPixels - 10,
                "Output glyph must remain at the same size and position, independent of available drawer height")
    }

    @Test("Idle music renders its automatic discovery explanation")
    func musicDisconnectedRenders() async throws {
        let provider = RenderMusicProvider(value: nil)
        let model = NowPlayingModel(provider: provider)
        let bitmap = try await render(NowPlayingView(model: model), name: "music-empty")
        #expect(brightPixels(bitmap, in: CGRect(x: 70, y: 14, width: 440, height: 65)) > 150,
                "Music heading and explanation must appear in the body")
        #expect(brightPixels(bitmap, in: CGRect(x: 12, y: 86, width: 450, height: 44)) > 30,
                "Automatic discovery status must remain visible below the heading")
        #expect(await provider.reads == 0)
        #expect(await provider.connections == 0)
        #expect(await provider.actions == 0)
    }

    @Test("Active music renders artwork, metadata, progress, and transport controls")
    func playingMusicRenders() async throws {
        let value = NowPlayingSnapshot(source: .music, title: "Synthetic render track", artist: "Fixture artist",
                                       album: "Fixture album", duration: 240, position: 80, isPlaying: true,
                                       artworkData: try artwork())
        let provider = RenderMusicProvider(value: value)
        let model = NowPlayingModel(provider: provider, enabledSources: [.music])
        await model.refreshNow()
        #expect(model.track?.title == value.title)
        // Artwork decoding is asynchronous; wait for readiness before sampling pixels.
        for _ in 0..<100 where model.track?.artwork == nil {
            try await Task.sleep(for: .milliseconds(20))
        }
        _ = try #require(model.track?.artwork)
        let bitmap = try await render(NowPlayingView(model: model), name: "music-playing")
        var greenArtworkPixels = 0
        for y in stride(from: 36, to: 114, by: 2) {
            for x in stride(from: 36, to: 114, by: 2) {
                guard let color = pixel(bitmap, x: x, y: y) else { continue }
                // Display color conversion changes the fixture's channels: the saved render samples
                // approximately (0.465, 0.891, 0.365). Assert its distinctive green dominance.
                if color.greenComponent > 0.65 && color.greenComponent - color.redComponent > 0.25
                    && color.greenComponent - color.blueComponent > 0.3 {
                    greenArtworkPixels += 1
                }
            }
        }
        #expect(greenArtworkPixels > 400, "Synthetic album art must render at the left of the player")
        for point in [CGPoint(x: 57, y: 37), CGPoint(x: 129, y: 37),
                      CGPoint(x: 57, y: 107), CGPoint(x: 105, y: 107)] {
            // The bottom-right corner carries the source app badge, so sample just inside it.
            let color = try #require(pixel(bitmap, x: Int(point.x), y: Int(point.y)))
            #expect(color.greenComponent - color.redComponent > 0.25,
                    "Album art must fill a square centered beside the title and artist, without side bars")
        }
        #expect(brightPixels(bitmap, in: CGRect(x: 140, y: 10, width: 400, height: 68)) > 150,
                "Track title and artist must be visible next to the artwork")
        #expect(brightPixels(bitmap, in: CGRect(x: 150, y: 156, width: 300, height: 65)) > 100,
                "Plain transport icons must remain visible below playback progress")
        #expect(await provider.reads == 1)
        #expect(await provider.connections == 0)
        #expect(await provider.actions == 0)
    }

    @Test("Calls connection state fits the notch and renders a connection action")
    func callsDisconnectedRenders() async throws {
        let model = CallActivityModel(accessibilityTrusted: { false })
        let bitmap = try await render(CallActivityView(model: model), name: "calls-empty")
        #expect(!model.isConnected)
        #expect(model.activeCall == nil)
        #expect(brightPixels(bitmap, in: CGRect(x: 15, y: 15, width: 480, height: 55)) > 150,
                "Call heading and connection explanation must be visible")
        #expect(brightPixels(bitmap, in: CGRect(x: 15, y: 100, width: 250, height: 65)) > 60,
                "The connection action must fit below the support details")
    }

    @Test("Inline output drawer renders only provider devices beneath the player")
    func outputDrawerRendersProviderDevices() async throws {
        let value = NowPlayingSnapshot(source: .music, title: "Synthetic render track", artist: "Fixture artist",
                                       album: "Fixture album", duration: 240, position: 80, isPlaying: true,
                                       artworkData: try artwork())
        let model = NowPlayingModel(provider: RenderMusicProvider(value: value), enabledSources: [.music])
        await model.refreshNow()
        let outputs = AudioOutputModel(provider: RenderAudioOutputProvider())
        await outputs.refreshNow()
        let bitmap = try await render(NowPlayingView(model: model, outputs: outputs, showingOutputs: true),
                                      name: "music-output-drawer", height: 500)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        try VNImageRequestHandler(cgImage: try #require(bitmap.cgImage)).perform([request])
        let visible = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ").lowercased()
        #expect(!visible.contains("sound output"), "The reference drawer has no extra heading")
        #expect(visible.contains("fixture speakers"))
        #expect(visible.contains("fixture headphones"))
        #expect(outputs.selectedID == 1)
    }

    private func render<Content: View>(_ content: Content, name: String, height: CGFloat = 310) async throws -> NSBitmapImageRep {
        let size = CGSize(width: 600, height: height)
        let host = NSHostingView(rootView: content.frame(width: size.width, height: size.height, alignment: .top)
            .background(.black).preferredColorScheme(.dark))
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        host.frame = CGRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        if let destination = ProcessInfo.processInfo.environment["BRIM_SNAPSHOT_DIR"], !destination.isEmpty {
            let directory = URL(fileURLWithPath: destination, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let image = NSImage(size: size)
            image.addRepresentation(bitmap)
            try ImageEncoder.pngDataPreservingAlpha(from: image)
                .write(to: directory.appendingPathComponent("\(name).png"), options: .atomic)
        }
        return bitmap
    }

    private func brightPixels(_ bitmap: NSBitmapImageRep, in area: CGRect) -> Int {
        var count = 0
        for y in Int(area.minY)..<Int(area.maxY) {
            for x in stride(from: Int(area.minX), to: Int(area.maxX), by: 2) {
                guard let color = pixel(bitmap, x: x, y: y) else { continue }
                if color.redComponent > 0.3 && color.greenComponent > 0.3 && color.blueComponent > 0.3 { count += 1 }
            }
        }
        return count
    }

    private func pixel(_ bitmap: NSBitmapImageRep, x: Int, y: Int) -> NSColor? {
        let scale = CGFloat(bitmap.pixelsWide) / 600
        return bitmap.colorAt(x: Int(CGFloat(x) * scale), y: Int(CGFloat(y) * scale))?.usingColorSpace(.deviceRGB)
    }

    private func artwork() throws -> Data {
        let context = try #require(CGContext(data: nil, width: 128, height: 128, bitsPerComponent: 8,
                                            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.1, green: 0.9, blue: 0.1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 128, height: 128))
        let image = NSImage(cgImage: try #require(context.makeImage()), size: CGSize(width: 128, height: 128))
        return try ImageEncoder.pngDataPreservingAlpha(from: image)
    }
}

private struct RenderAudioOutputProvider: AudioOutputProviding {
    func snapshot() async throws -> AudioOutputSnapshot {
        AudioOutputSnapshot(devices: [AudioOutputDevice(id: 1, name: "Fixture speakers", icon: "speaker.wave.2.fill"),
                                       AudioOutputDevice(id: 2, name: "Fixture headphones", icon: "headphones")], selectedID: 1)
    }
    func select(_ id: UInt32) async throws -> AudioOutputSnapshot { try await snapshot() }
}

private actor RenderMusicProvider: NowPlayingProviding {
    let value: NowPlayingSnapshot?
    private(set) var reads = 0
    private(set) var connections = 0
    private(set) var actions = 0

    init(value: NowPlayingSnapshot?) { self.value = value }
    func connect(_ source: NowPlayingSource) async throws { connections += 1 }
    func snapshot(_ source: NowPlayingSource) async throws -> NowPlayingSnapshot? { reads += 1; return value }
    func perform(_ command: NowPlayingCommand, expected: NowPlayingSnapshot, token: NowPlayingActionToken) async throws {
        actions += 1
    }
}
