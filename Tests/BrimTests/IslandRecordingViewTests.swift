import AppKit
import SwiftUI
import Testing
@testable import Brim

@MainActor
@Suite(.serialized)
struct IslandRecordingViewTests {
    @Test("Recording and music render a single red recording dot and detached music activity", arguments: [false, true])
    func recordingAndMusic(expanded: Bool) async throws {
        let recording = ScreenRecordingModel(probe: { ScreenRecordingEvidence(identity: "fixture") })
        await recording.refreshNow()
        let music = NowPlayingModel(provider: IslandRenderMusicProvider(), enabledSources: [.music])
        await music.refreshNow()
        let presentation = NotchPresentation()
        presentation.isExpanded = expanded
        presentation.geometry = NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            notchWidth: 184, notchHeight: 32, hasLiveActivity: true, hasSecondaryActivity: true)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let size = presentation.geometry.hostingFrame.size
        let host = NSHostingView(rootView: NotchShelfView(presentation: presentation, store: ShelfStore(directory: directory),
            nowPlaying: music, calls: CallActivityModel(accessibilityTrusted: { false }), recording: recording))
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.contentView = host
        defer { window.close() }
        host.frame = CGRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(750))
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let scale = CGFloat(bitmap.pixelsWide) / size.width
        let frame = presentation.geometry.secondaryFrame(expanded: expanded)
        let x = Int((frame.midX - presentation.geometry.hostingFrame.minX) * scale)
        let y = Int(17 * scale)
        let bubble = try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
        #expect(bubble.alphaComponent > 0.9, "Detached bubble must not be clipped outside the main shell")
        let gapX = Int((frame.minX - 4 - presentation.geometry.hostingFrame.minX) * scale)
        let gap = try #require(bitmap.colorAt(x: gapX, y: y))
        #expect(gap.alphaComponent < 0.01, "The bubble must be separated by a transparent gap")
        var redPixels = 0
        for row in 0..<bitmap.pixelsHigh {
            for col in stride(from: 0, to: bitmap.pixelsWide, by: 2) {
                guard let color = bitmap.colorAt(x: col, y: row)?.usingColorSpace(.deviceRGB) else { continue }
                if color.alphaComponent > 0.8 && color.redComponent > 0.6 && color.greenComponent < 0.4 { redPixels += 1 }
            }
        }
        #expect(redPixels > 10)
        let output = URL(fileURLWithPath: "/tmp/brim-island-renders", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let image = NSImage(size: size)
        image.addRepresentation(bitmap)
        try ImageEncoder.pngDataPreservingAlpha(from: image).write(to: output.appendingPathComponent(expanded ? "recording-expanded.png" : "recording-compact.png"))
    }
}

private struct IslandRenderMusicProvider: NowPlayingProviding {
    func connect(_ source: NowPlayingSource) async throws {}
    func snapshot(_ source: NowPlayingSource) async throws -> NowPlayingSnapshot? {
        NowPlayingSnapshot(source: .music, title: "Test music", artist: "Fixture", album: "Fixture", duration: 240, position: 60, isPlaying: true)
    }
    func perform(_ command: NowPlayingCommand, expected: NowPlayingSnapshot, token: NowPlayingActionToken) async throws {}
}
