import AppKit
import SwiftUI
import Testing
@testable import Brim

private actor TransitionRecordingProbe {
    var active = true
    func stop() { active = false }
    func read() -> ScreenRecordingEvidence? { active ? ScreenRecordingEvidence(identity: "fixture") : nil }
}

@MainActor
@Suite(.serialized)
struct WaveformTransitionTests {
    @Test("Waveform stays anchored after recording ends or music and timer are switched", arguments: [false, true], [false, true])
    func waveformStaysAnchored(floating: Bool, switchingTimer: Bool) async throws {
        let probe = TransitionRecordingProbe()
        if switchingTimer { await probe.stop() }
        let recording = ScreenRecordingModel(probe: { await probe.read() })
        await recording.refreshNow()
        // The compact track title has its own render test; here the waveform's anchor is under test.
        let settings = AppSettings.shared
        let savedTitles = (settings.notchTrackTitle, settings.keepSongNameVisible)
        settings.notchTrackTitle = false
        settings.keepSongNameVisible = false
        defer { (settings.notchTrackTitle, settings.keepSongNameVisible) = savedTitles }
        let music = NowPlayingModel(provider: TransitionPlayingMusic(), enabledSources: [.music])
        await music.refreshNow()
        let timer = NativeTimerActivity(id: "fixture", title: "Fixture timer", duration: 240, endDate: nil, pausedRemaining: 204)
        let timers = NativeTimerModel(probe: { switchingTimer ? timer : nil })
        await timers.refreshNow()
        let presentation = NotchPresentation()
        presentation.isExpanded = switchingTimer
        presentation.geometry = NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            notchWidth: floating ? 0 : 184, notchHeight: floating ? 0 : 32)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let size = presentation.geometry.hostingFrame.size
        let host = NSHostingView(rootView: NotchShelfView(presentation: presentation, store: ShelfStore(directory: directory),
            nowPlaying: music, calls: CallActivityModel(accessibilityTrusted: { false }), recording: recording,
            timers: timers))
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = host
        defer { window.close() }
        host.frame = CGRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        if switchingTimer {
            for activity in [IslandActivity.music, .timer, .music, .timer] {
                withAnimation(NotchMotion.layout(reduceMotion: false)) {
                    presentation.selectedActivity = activity
                }
                try await Task.sleep(for: .milliseconds(180))
            }
        } else {
            await probe.stop()
            await recording.refreshNow()
        }
        // Sample the canvas: bright waveform pixels, and any that fall outside the expected slot.
        func sample() throws -> (bright: Int, outside: Int) {
            host.layoutSubtreeIfNeeded()
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let scale = CGFloat(bitmap.pixelsWide) / size.width
            let geometry = presentation.geometry
            let bubble = geometry.secondaryFrame(expanded: true)
            let expected = switchingTimer
                ? CGRect(x: bubble.midX - geometry.hostingFrame.minX - 10, y: 0, width: 20, height: geometry.secondarySize.height)
                // The waveform hugs the right wing's outer inset (CompactLayout.wingOuter); it may
                // be up to 32pt wide, and a shift of even a few points left of that fails.
                : CGRect(x: size.width / 2 + geometry.collapsedSize.width / 2 - CompactLayout.wingOuter - 32,
                         y: 0, width: 34, height: geometry.collapsedSize.height)
            var bright = 0
            var outside = 0
            let sampledHeight = switchingTimer ? Int(geometry.secondarySize.height * scale) : bitmap.pixelsHigh
            let sampledLeft = switchingTimer ? Int((size.width / 2 + geometry.expandedSize.width / 2) * scale) : bitmap.pixelsWide / 2
            for y in 0..<sampledHeight {
                for x in sampledLeft..<bitmap.pixelsWide {
                    guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                          color.alphaComponent > 0.5, color.redComponent > 0.5,
                          color.greenComponent > 0.5, color.blueComponent > 0.5 else { continue }
                    bright += 1
                    if !expected.contains(CGPoint(x: CGFloat(x) / scale, y: CGFloat(y) / scale)) { outside += 1 }
                }
            }
            return (bright, outside)
        }
        // Under a loaded test run the transitions finish late; wait (bounded) for the shell to settle
        // before the strict checks, instead of sampling a frame that is still animating.
        try await Task.sleep(for: .milliseconds(800))
        for _ in 0..<20 {
            let frame = try sample()
            if frame.bright > 10 && frame.outside == 0 { break }
            try await Task.sleep(for: .milliseconds(150))
        }
        for _ in 0..<5 {
            try await Task.sleep(for: .milliseconds(230))
            let frame = try sample()
            #expect(frame.outside == 0, "Animated waveform must stay in the trailing slot after the shell settles")
            #expect(frame.bright > 10, "Playing waveform must remain visible")
        }
    }
}

private struct TransitionPlayingMusic: NowPlayingProviding {
    func connect(_ source: NowPlayingSource) async throws {}
    func snapshot(_ source: NowPlayingSource) async throws -> NowPlayingSnapshot? {
        NowPlayingSnapshot(source: .music, title: "Fixture", artist: "Fixture", album: "Fixture", duration: 240, position: 60, isPlaying: true)
    }
    func perform(_ command: NowPlayingCommand, expected: NowPlayingSnapshot, token: NowPlayingActionToken) async throws {}
}
