import AppKit
import SwiftUI
import Testing
@testable import Brim

@MainActor
@Suite(.serialized)
struct IslandCompactDesignTests {
    @Test("Compact recording uses exactly one filled leading indicator", arguments: [true, false])
    func singleLeadingRecordingDot(floating: Bool) async throws {
        let recording = ScreenRecordingModel(probe: { ScreenRecordingEvidence(identity: "fixture") })
        await recording.refreshNow()
        let result = try await render(recording: recording, timer: NativeTimerModel(probe: { nil }), floating: floating)
        var redX: [Int] = []
        for y in 0..<result.pixelsHigh {
            for x in 0..<result.pixelsWide {
                if let color = result.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                   color.redComponent > 0.8 && color.greenComponent < 0.5 && color.blueComponent < 0.5 {
                    redX.append(x)
                }
            }
        }
        #expect(!redX.isEmpty)
        #expect((redX.max() ?? 0) < result.pixelsWide / 2, "Only the leading side has a recording indicator")
        let width = try #require(redX.max()) - (try #require(redX.min()))
        #expect(width < 30, "The red region must be a small solid status dot")
    }

    @Test("Native timer renders orange countdown in the compact pill")
    func timerCountdown() async throws {
        let timer = NativeTimerModel(probe: {
            NativeTimerActivity(id: "fixture", title: "Tea", duration: 180, endDate: nil, pausedRemaining: 148)
        })
        await timer.refreshNow()
        let result = try await render(recording: ScreenRecordingModel(probe: { nil }), timer: timer, floating: true)
        var orangeOnRight = 0
        for y in 0..<result.pixelsHigh {
            for x in (result.pixelsWide / 2)..<result.pixelsWide {
                if let color = result.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                   color.redComponent > 0.8 && color.greenComponent > color.blueComponent + 0.25
                    && color.greenComponent < color.redComponent - 0.1 { orangeOnRight += 1 }
            }
        }
        #expect(orangeOnRight > 40, "Time remaining must be visible in orange on the trailing side")
    }

    private func render(recording: ScreenRecordingModel, timer: NativeTimerModel, floating: Bool) async throws -> NSBitmapImageRep {
        let presentation = NotchPresentation()
        presentation.geometry = NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            notchWidth: floating ? 0 : 184, notchHeight: floating ? 0 : 32)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let content = NotchShelfView(presentation: presentation, store: ShelfStore(directory: directory),
            nowPlaying: NowPlayingModel(provider: CompactEmptyPlayer(), enabledSources: []),
            calls: CallActivityModel(accessibilityTrusted: { false }), recording: recording, timers: timer)
        let size = CGSize(width: 740, height: 100)
        let host = NSHostingView(rootView: content.padding(.top, 14).background(Color(white: 0.22)))
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        host.frame = CGRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(250))
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let folder = URL(fileURLWithPath: "/tmp/brim-native-design", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let image = NSImage(size: size)
        image.addRepresentation(bitmap)
        let name = recording.activeRecording != nil ? "recording" : "timer"
        try ImageEncoder.pngDataPreservingAlpha(from: image).write(to: folder.appendingPathComponent("\(name)-\(floating ? "capsule" : "notch").png"))
        return bitmap
    }
}

private struct CompactEmptyPlayer: NowPlayingProviding {
    func connect(_ source: NowPlayingSource) async throws {}
    func snapshot(_ source: NowPlayingSource) async throws -> NowPlayingSnapshot? { nil }
    func perform(_ command: NowPlayingCommand, expected: NowPlayingSnapshot, token: NowPlayingActionToken) async throws {}
}
