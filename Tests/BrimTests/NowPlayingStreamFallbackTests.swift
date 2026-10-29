import AppKit
import SwiftUI
import Testing
import Vision

@testable import Brim

@MainActor
@Suite(.serialized)
struct NowPlayingStreamFallbackTests {
    private func song(source: NowPlayingSource, at date: Date) -> MediaRemoteStreamMessage {
        .nowPlaying(.init(bundle: source.bundleID, title: "Low Life", artist: "Future", album: "EVOL",
            duration: 313, elapsed: 30, rate: 1, timestamp: date, isPlaying: true, artwork: Data()))
    }

    @Test(arguments: [NowPlayingSource.youtubeApp, .music])
    func deniedSupplementalAccessDoesNotEraseTheSystemSong(source: NowPlayingSource) async {
        let provider = SupplementalAccessDeniedPlayer()
        let model = NowPlayingModel(provider: provider, enabledSources: [source], stream: nil)
        defer { model.stop() }
        let anchor = Date()
        model.handleStream(song(source: source, at: anchor))

        await model.refreshNow()
        await model.refreshNow()

        #expect(model.track?.title == "Low Life")
        #expect(model.isInIsland(now: anchor.addingTimeInterval(20)))
        #expect(model.track?.position(at: anchor.addingTimeInterval(20)) == 50)
        #expect(model.accessSource == nil)
        #expect(model.status.isEmpty)
        #expect(model.sourceStatus[source]?.isEmpty == false)
    }

    @Test func emptySupplementalPollsDoNotEraseTheSystemSong() async {
        let model = NowPlayingModel(provider: StubNowPlayingProvider(), enabledSources: [.youtubeApp], stream: nil)
        defer { model.stop() }
        model.handleStream(song(source: .youtubeApp, at: Date()))

        for _ in 0..<3 { await model.refreshNow() }

        #expect(model.track?.title == "Low Life")
        #expect(model.isInIsland())
    }

    @Test func anIdlePlayerDoesNotReplaceThePlayingSystemSong() async {
        let provider = StubNowPlayingProvider()
        await provider.set([NowPlayingSnapshot(source: .music, title: "Paused song", artist: "Artist", album: "",
            duration: 200, position: 10, isPlaying: false)])
        let model = NowPlayingModel(provider: provider, enabledSources: [.youtubeApp, .music], stream: nil)
        defer { model.stop() }
        model.handleStream(song(source: .youtubeApp, at: Date()))

        await model.refreshNow()

        #expect(model.track?.title == "Low Life")
        #expect(model.isInIsland())
    }

    @Test(arguments: [MediaRemoteStreamMessage.none, .unavailable,
        .nowPlaying(.init(bundle: "company.thebrowser.Browser", title: "Video", artist: "", album: "",
            duration: 10, elapsed: 0, rate: 1, timestamp: Date(), isPlaying: true, artwork: nil))])
    func aSystemSessionEndingAllowsEmptyPollsToClearTheSong(message: MediaRemoteStreamMessage) async {
        let model = NowPlayingModel(provider: StubNowPlayingProvider(), enabledSources: [.youtubeApp], stream: nil)
        defer { model.stop() }
        model.handleStream(song(source: .youtubeApp, at: Date()))
        await model.refreshNow()

        model.handleStream(message)
        for _ in 0..<3 { await model.refreshNow() }

        #expect(model.track == nil)
        #expect(!model.isInIsland())
    }

    @Test func quittingThePlayerClearsTheSongEvenWithoutASystemEvent() async {
        let provider = StubNowPlayingProvider()
        await provider.setRunningSources([.youtubeApp])
        let model = NowPlayingModel(provider: provider, stream: nil)
        defer { model.stop() }
        model.handleStream(song(source: .youtubeApp, at: Date()))
        await model.refreshNow()

        await provider.setRunningSources([])
        await model.refreshNow()

        #expect(model.track == nil)
    }

    @Test(arguments: HomeWidgetSize.allCases)
    func homeWidgetRendersTheSongAfterDeniedPolls(size: HomeWidgetSize) async throws {
        let model = NowPlayingModel(provider: SupplementalAccessDeniedPlayer(), enabledSources: [.youtubeApp], stream: nil)
        defer { model.stop() }
        model.handleStream(song(source: .youtubeApp, at: Date()))
        for _ in 0..<3 { await model.refreshNow() }

        let volume = PlayerVolumeModel(read: { .init(level: 0.65, muted: false) }, write: { _ in true })
        let cardSize = CGSize(width: size.width, height: HomeWidgetGrid.unit)
        let canvas = CGSize(width: cardSize.width + 24, height: cardSize.height + 24)
        let host = NSHostingView(rootView: HomeIdlePlayerCard(model: model, size: size, volumeModel: volume)
            .frame(width: cardSize.width, height: cardSize.height).padding(12)
            .background(Color(white: 0.12)).preferredColorScheme(.dark))
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: canvas), styleMask: [.borderless],
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        host.frame = CGRect(origin: .zero, size: canvas)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(300))
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        try VNImageRequestHandler(cgImage: #require(bitmap.cgImage), options: [:]).perform([request])
        let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ").lowercased()
        #expect(text.contains("low life"))
        #expect(text.contains("future"))
        #expect(!text.contains("not playing"))

        let output = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent(".context/music-stream-home-\(size.rawValue).png")
        try #require(bitmap.representation(using: .png, properties: [:])).write(to: output)
    }
}

private actor SupplementalAccessDeniedPlayer: NowPlayingProviding {
    func connect(_ source: NowPlayingSource) async throws {}
    func snapshot(_ source: NowPlayingSource) async throws -> NowPlayingSnapshot? {
        throw source == .youtubeApp ? NowPlayingFailure.accessibility : NowPlayingFailure.permission(source.name)
    }
    func perform(_ command: NowPlayingCommand, expected: NowPlayingSnapshot, token: NowPlayingActionToken) async throws {}
}
