import AppKit
import Testing
@testable import Brim

struct PlaybackReconcilerTests {
    private let t0 = Date(timeIntervalSince1970: 1_000)
    private func snap(playing: Bool = true, position: TimeInterval = 40, title: String = "Song",
                      favorite: Bool? = nil) -> NowPlayingSnapshot {
        NowPlayingSnapshot(source: .music, title: title, artist: "Artist", album: "Album", duration: 200,
                           position: position, isPlaying: playing, isFavorite: favorite)
    }

    @Test func tapFlipsDisplayedStateAtOnceAndFreezesElapsed() {
        var overlay = OptimisticPlayback()
        let wants = overlay.togglePlayPause(displayed: snap(playing: true), position: 42.5, now: t0)
        #expect(wants == false)
        // The source still says "playing": the overlay hides that.
        let display = overlay.apply(to: snap(playing: true, position: 40), sampleAnchor: t0.addingTimeInterval(-2), now: t0)
        #expect(display.snapshot.isPlaying == false)
        #expect(display.snapshot.position == 42.5)
        #expect(display.anchor == t0)
    }

    @Test func resumeRestartsTheClockFromTheFrozenSecond() {
        var overlay = OptimisticPlayback()
        overlay.togglePlayPause(displayed: snap(playing: false, position: 70), position: 70, now: t0)
        let display = overlay.apply(to: snap(playing: false, position: 70), sampleAnchor: t0, now: t0.addingTimeInterval(0.1))
        let track = NowPlayingTrack(snapshot: display.snapshot, artwork: nil, sampledAt: display.anchor ?? t0, stallCap: nil)
        #expect(display.snapshot.isPlaying)
        #expect(abs(track.position(at: t0.addingTimeInterval(2)) - 72) < 0.001)
    }

    @Test func playPauseConfirmsOnlyAfterSettleWindow() {
        var overlay = OptimisticPlayback()
        overlay.togglePlayPause(displayed: snap(playing: true), position: 10, now: t0)
        #expect(overlay.reconcile(observed: snap(playing: false), position: 10, now: t0.addingTimeInterval(0.1)).isEmpty)
        #expect(overlay.play != nil)
        #expect(overlay.reconcile(observed: snap(playing: false), position: 10, now: t0.addingTimeInterval(0.4)) == [.confirmed])
        #expect(overlay.isEmpty)
    }

    @Test func contradictingSourceRollsBackOnlyAfterGrace() {
        var overlay = OptimisticPlayback()
        overlay.togglePlayPause(displayed: snap(playing: true), position: 10, now: t0)
        #expect(overlay.reconcile(observed: snap(playing: true), position: 10, now: t0.addingTimeInterval(1.4)).isEmpty)
        #expect(overlay.reconcile(observed: snap(playing: true), position: 10, now: t0.addingTimeInterval(1.6)) == [.rolledBack])
        let display = overlay.apply(to: snap(playing: true), sampleAnchor: t0, now: t0.addingTimeInterval(1.6))
        #expect(display.snapshot.isPlaying)
    }

    @Test func failedCommandDropsEveryIntentImmediately() {
        var overlay = OptimisticPlayback()
        overlay.togglePlayPause(displayed: snap(), position: 5, now: t0)
        overlay.startSkip(forward: true, displayed: snap(), position: 5, now: t0)
        overlay.fail()
        #expect(overlay.isEmpty)
    }

    @Test func nextShowsSkeletonAndResetsElapsedUntilTheSongChanges() {
        var overlay = OptimisticPlayback()
        overlay.startSkip(forward: true, displayed: snap(), position: 90, now: t0)
        let during = overlay.apply(to: snap(position: 91), sampleAnchor: t0, now: t0.addingTimeInterval(0.2))
        #expect(during.isTransitioning)
        #expect(during.snapshot.position == 0)
        #expect(overlay.reconcile(observed: snap(position: 0, title: "Other"), position: 0, now: t0.addingTimeInterval(0.5)) == [.confirmed])
        #expect(overlay.skip == nil)
    }

    @Test func skeletonEndsAfterGraceIfTheSongNeverChanges() {
        var overlay = OptimisticPlayback()
        overlay.startSkip(forward: true, displayed: snap(), position: 90, now: t0)
        #expect(overlay.reconcile(observed: snap(), position: 90, now: t0.addingTimeInterval(2)) == [.rolledBack])
        #expect(!overlay.apply(to: snap(), sampleAnchor: t0, now: t0.addingTimeInterval(2)).isTransitioning)
    }

    @Test func previousPastThreeSecondsRestartsInsteadOfSkipping() {
        var overlay = OptimisticPlayback()
        overlay.startSkip(forward: false, displayed: snap(), position: 30, now: t0)
        #expect(overlay.skip == nil)
        #expect(overlay.seek?.target == 0)
        var early = OptimisticPlayback()
        early.startSkip(forward: false, displayed: snap(), position: 1.5, now: t0)
        #expect(early.skip != nil)
    }

    @Test func seekShowsTargetAtOnceAndConfirmsWhenTheSourceArrives() {
        var overlay = OptimisticPlayback()
        overlay.startSeek(to: 120, displayed: snap(playing: true), now: t0)
        #expect(overlay.apply(to: snap(position: 41), sampleAnchor: t0, now: t0).snapshot.position == 120)
        #expect(overlay.reconcile(observed: snap(position: 42), position: 120, now: t0.addingTimeInterval(0.5)).isEmpty)
        #expect(overlay.reconcile(observed: snap(position: 120.6), position: 120, now: t0.addingTimeInterval(0.6)) == [.confirmed])
    }

    @Test func favoriteFlipsAtOnceAndRollsBack() {
        var overlay = OptimisticPlayback()
        overlay.setFavorite(true, now: t0)
        #expect(overlay.apply(to: snap(favorite: false), sampleAnchor: t0, now: t0).snapshot.isFavorite == true)
        #expect(overlay.reconcile(observed: snap(favorite: false), position: 0, now: t0.addingTimeInterval(2)) == [.rolledBack])
    }

    @Test func nothingPlayingClearsPendingIntents() {
        var overlay = OptimisticPlayback()
        overlay.togglePlayPause(displayed: snap(), position: 5, now: t0)
        #expect(overlay.reconcile(observed: nil, position: 0, now: t0.addingTimeInterval(0.1)) == [.rolledBack])
        #expect(overlay.isEmpty)
    }

    @Test func nextDeadlineIsTheOldestIntentPlusGrace() {
        var overlay = OptimisticPlayback()
        #expect(overlay.nextDeadline == nil)
        overlay.setShuffle(true, now: t0.addingTimeInterval(1))
        overlay.setFavorite(true, now: t0)
        #expect(overlay.nextDeadline == t0.addingTimeInterval(OptimisticPlayback.grace))
    }
}

struct ElapsedClockTests {
    private let t0 = Date(timeIntervalSince1970: 500)

    @Test func advancesByRateSinceTheAnchor() {
        let clock = ElapsedClock(position: 10, anchor: t0, rate: 1, duration: 100, stallCap: nil)
        #expect(clock.position(at: t0.addingTimeInterval(4.5)) == 14.5)
        let double = ElapsedClock(position: 10, anchor: t0, rate: 2, duration: 100, stallCap: nil)
        #expect(double.position(at: t0.addingTimeInterval(5)) == 20)
    }

    @Test func pausedRateHoldsAndClampsToDuration() {
        #expect(ElapsedClock(position: 10, anchor: t0, rate: 0, duration: 100, stallCap: nil)
            .position(at: t0.addingTimeInterval(30)) == 10)
        #expect(ElapsedClock(position: 95, anchor: t0, rate: 1, duration: 100, stallCap: nil)
            .position(at: t0.addingTimeInterval(30)) == 100)
    }

    @Test func stallCapStopsExtrapolationOfStalePolls() {
        let clock = ElapsedClock(position: 10, anchor: t0, rate: 1, duration: 100, stallCap: 3)
        #expect(clock.position(at: t0.addingTimeInterval(30)) == 13)
        #expect(clock.position(at: t0.addingTimeInterval(-5)) == 10)
    }

    @Test func streamedTrackKeepsAdvancingWithoutNewSamples() {
        let snapshot = NowPlayingSnapshot(source: .music, title: "S", artist: "A", album: "", duration: 300, position: 20, isPlaying: true)
        let track = NowPlayingTrack(snapshot: snapshot, artwork: nil, sampledAt: t0, stallCap: nil)
        #expect(track.position(at: t0.addingTimeInterval(60)) == 80)
    }
}

struct MediaRemoteStreamParserTests {
    @Test func parsesNowPlayingLine() {
        let line = #"{"type":"nowplaying","bundle":"com.apple.Music","title":"Kill Bill","artist":"SZA","album":"SOS","duration":153.2,"elapsed":69.5,"rate":1,"timestamp":1792704505.5,"playing":true}"#
        guard case .nowPlaying(let payload)? = MediaRemoteStreamMessage.parse(line) else { Issue.record("not parsed"); return }
        #expect(payload.title == "Kill Bill")
        #expect(payload.isPlaying)
        #expect(payload.elapsed == 69.5)
        #expect(payload.timestamp == Date(timeIntervalSince1970: 1792704505.5))
        #expect(MediaRemoteStreamMessage.Payload.source(forBundle: payload.bundle) == .music)
    }

    @Test func parsesRepliesNoneAndRejectsGarbage() {
        #expect(MediaRemoteStreamMessage.parse(#"{"type":"reply","id":7,"result":"sent 0"}"#) == .reply(id: 7, result: "sent 0"))
        #expect(MediaRemoteStreamMessage.parse(#"{"type":"none"}"#) == MediaRemoteStreamMessage.none)
        for junk in ["", "not json", #"{"type":"nowplaying"}"#, #"{"type":"nowplaying","bundle":"x","title":""}"#, #"{"type":"weird"}"#] {
            #expect(MediaRemoteStreamMessage.parse(junk) == nil)
        }
    }

    @Test func decodesArtworkAndKeepsSnapshotAnchoredAtTheEventTimestamp() {
        let png = Data([1, 2, 3]).base64EncodedString()
        let line = #"{"type":"nowplaying","bundle":"com.spotify.client","title":"T","artist":"A","album":"","duration":10,"elapsed":2,"rate":0,"timestamp":100,"playing":false,"artwork":"\#(png)"}"#
        guard case .nowPlaying(let payload)? = MediaRemoteStreamMessage.parse(line) else { Issue.record("not parsed"); return }
        #expect(payload.artwork == Data([1, 2, 3]))
        let snapshot = payload.snapshot(source: .spotify, previous: nil)
        #expect(snapshot.position == 2)
        #expect(snapshot.playbackRate == 0)
    }

    @Test func unknownBundlesAreNotMapped() {
        #expect(MediaRemoteStreamMessage.Payload.source(forBundle: "company.thebrowser.Browser") == nil)
        #expect(MediaRemoteStreamMessage.Payload.source(forBundle: "com.google.Chrome") == nil)
        #expect(MediaRemoteStreamMessage.Payload.source(forBundle: "com.google.Chrome.app.cinhimbnkkaeohfgghhklpknlkffjgod") == .youtubeApp)
    }

    @Test func lineBufferJoinsSplitChunksAndDropsOversizedLines() {
        var buffer = LineBuffer(limit: 10)
        #expect(buffer.feed(Data("abc".utf8)).isEmpty)
        #expect(buffer.feed(Data("def\nxy".utf8)) == ["abcdef"])
        #expect(buffer.feed(Data("z\n01234567890123\nok\n".utf8)) == ["xyz", "ok"])
    }
}

@MainActor
struct OptimisticModelTests {
    private func snap(playing: Bool, title: String = "Song") -> NowPlayingSnapshot {
        NowPlayingSnapshot(source: .music, title: title, artist: "Artist", album: "Album", duration: 180, position: 40, isPlaying: playing)
    }

    @Test func playPauseFlipsTheUIBeforeTheCommandReturns() async {
        let provider = StubNowPlayingProvider()
        await provider.set([snap(playing: true)])
        let model = NowPlayingModel(provider: provider, enabledSources: [.music], stream: nil)
        await model.refreshNow()
        let task = model.command(.playPause)
        // No await between the tap and this read: the flip is synchronous.
        #expect(model.track?.isPlaying == false)
        await task?.value
        #expect(model.track?.isPlaying == false)
        #expect(!model.isBusy)
    }

    @Test func rapidTapsAreNeverDroppedWhileTheFirstIsInFlight() async {
        let provider = StubNowPlayingProvider()
        await provider.set([snap(playing: true)])
        let model = NowPlayingModel(provider: provider, enabledSources: [.music], stream: nil)
        await model.refreshNow()
        let first = model.command(.playPause)
        let second = model.command(.playPause)
        #expect(first != nil && second != nil)
        #expect(model.track?.isPlaying == true)
        await second?.value
    }

    @Test func failedCommandRollsTheUIBackAndExplains() async {
        let provider = StubNowPlayingProvider()
        await provider.set([snap(playing: true)])
        await provider.setCommandFailure(true)
        let model = NowPlayingModel(provider: provider, enabledSources: [.music], stream: nil)
        await model.refreshNow()
        let task = model.command(.playPause)
        #expect(model.track?.isPlaying == false)
        await task?.value
        #expect(model.track?.isPlaying == true)
        #expect(model.commandError != nil)
    }

    @Test func nextShowsSkeletonThenClearsWhenTheNewSongArrives() async {
        let provider = StubNowPlayingProvider()
        await provider.set([snap(playing: true)])
        let model = NowPlayingModel(provider: provider, enabledSources: [.music], stream: nil)
        await model.refreshNow()
        let task = model.command(.next)
        #expect(model.track?.isTransitioning == true)
        await task?.value
        try? await Task.sleep(for: .milliseconds(350))
        await provider.set([snap(playing: true, title: "Next song")])
        await model.refreshNow()
        #expect(model.track?.title == "Next song")
        #expect(model.track?.isTransitioning == false)
    }

    @Test func contradictingSamplesRollBackAfterTheGraceWindow() async {
        let provider = StubNowPlayingProvider()
        await provider.set([snap(playing: true)])
        let start = Date()
        var now = start
        let model = NowPlayingModel(provider: provider, enabledSources: [.music], artworkNow: { now }, stream: nil)
        await model.refreshNow()
        let task = model.command(.playPause)
        await task?.value
        now = start.addingTimeInterval(0.5)
        await model.refreshNow()      // source still says playing, inside the grace window
        #expect(model.track?.isPlaying == false)
        now = start.addingTimeInterval(2)
        await model.refreshNow()
        #expect(model.track?.isPlaying == true)
    }
}

struct PlayingNextQueueTests {
    private let us = "\u{1F}"

    @Test func parsesScriptOutputAndSkipsMalformedRows() {
        let output = "5\(us)A1\(us)Paper Moons\(us)Lumen Park\(us)201.5\n"
            + "bad row\n"
            + "6\(us)A2\(us)Low Tide\(us)Harbor Hymns\(us)180\n"
            + "0\(us)A3\(us)Zero index\(us)X\(us)1\n"
            + "7\(us)\(us)No id\(us)X\(us)1\n"
        let items = QueueParsing.parse(output)
        #expect(items.map(\.title) == ["Paper Moons", "Low Tide"])
        #expect(items.first?.index == 5)
        #expect(items.first?.duration == 201.5)
    }

    @Test func parsingHonoursTheLimit() {
        let output = (1...30).map { "\($0)\(us)id\($0)\(us)T\($0)\(us)A\(us)1" }.joined(separator: "\n")
        #expect(QueueParsing.parse(output, limit: 12).count == 12)
        #expect(QueueParsing.parse("").isEmpty)
    }

    @Test func movingToTopKeepsTheOtherRowsInOrder() {
        let items = (1...4).map { QueueItem(index: $0, persistentID: "p", title: "T\($0)", artist: "", duration: 1) }
        let moved = QueueParsing.movingToTop(items, id: items[2].id)
        #expect(moved.map(\.title) == ["T3", "T1", "T2", "T4"])
        #expect(QueueParsing.movingToTop(items, id: items[0].id) == items)
        #expect(QueueParsing.movingToTop(items, id: "missing") == items)
    }

    @Test func spotifyOffersNoQueue() {
        #expect(QueueCapability.supportsQueue(.music))
        for source in NowPlayingSource.allCases where source != .spotify { #expect(QueueCapability.supportsQueue(source)) }
        #expect(!QueueCapability.supportsQueue(.spotify))
        #expect(!QueueCapability.supportsQueue(nil))
    }

    @MainActor @Test func modelLoadsOnceForTheSameSongAndClearsForOtherSources() async {
        var reads = 0
        let model = PlayingNextModel(read: { _ in reads += 1; return "2\(self.us)i\(self.us)Next\(self.us)Art\(self.us)10" }, perform: { _ in "" })
        func track(_ source: NowPlayingSource) -> NowPlayingTrack {
            NowPlayingTrack(snapshot: NowPlayingSnapshot(source: source, title: "S", artist: "A", album: "", duration: 100, position: 1, isPlaying: true), artwork: nil)
        }
        model.refresh(for: track(.music))
        try? await Task.sleep(for: .milliseconds(100))
        #expect(model.items.count == 1)
        model.refresh(for: track(.music))
        try? await Task.sleep(for: .milliseconds(50))
        #expect(reads == 1)
        model.refresh(for: track(.spotify))
        #expect(model.items.isEmpty)
    }
}

struct LiquidPlayerPolicyTests {
    @Test func sizesGrowFromMiniToExpandedSharingAWidth() {
        let mini = LiquidPlayerPolicy.size(for: .mini), player = LiquidPlayerPolicy.size(for: .player)
        let expanded = LiquidPlayerPolicy.size(for: .expanded)
        #expect(mini.height < player.height && player.height < expanded.height)
        #expect(player.width == expanded.width && mini.width < player.width)
    }

    @Test func swipeUpGrowsAndSwipeDownShrinksWithinBounds() {
        let player = LiquidPlayerPolicy.size(for: .player).height
        #expect(LiquidPlayerPolicy.height(afterScrollDeltaY: -50, from: player) == player + 50)
        #expect(LiquidPlayerPolicy.height(afterScrollDeltaY: 60, from: player) == player - 60)
        #expect(LiquidPlayerPolicy.height(afterScrollDeltaY: -9_999, from: player) == LiquidPlayerPolicy.maxHeight)
        #expect(LiquidPlayerPolicy.height(afterScrollDeltaY: 9_999, from: player) == LiquidPlayerPolicy.minHeight)
        #expect(LiquidPlayerPolicy.height(afterScrollDeltaY: .nan, from: player) == player)
    }

    @Test func releaseSnapsToTheNearestSizeAndMomentumNudgesIt() {
        #expect(LiquidPlayerPolicy.snap(height: 70) == .mini)
        #expect(LiquidPlayerPolicy.snap(height: 180) == .player)
        #expect(LiquidPlayerPolicy.snap(height: 500) == .expanded)
        // Just short of the midpoint, but still moving up: settles on the bigger size.
        let mid = (LiquidPlayerPolicy.size(for: .player).height + LiquidPlayerPolicy.size(for: .expanded).height) / 2
        #expect(LiquidPlayerPolicy.snap(height: mid - 10) == .player)
        #expect(LiquidPlayerPolicy.snap(height: mid - 10, velocity: 200) == .expanded)
    }

    @Test func clickStepsThroughSizesAndWraps() {
        #expect(LiquidPlayerPolicy.next(.mini) == .player)
        #expect(LiquidPlayerPolicy.next(.player) == .expanded)
        #expect(LiquidPlayerPolicy.next(.expanded) == .mini)
    }

    @Test func wheelStepsOneSizeAndStopsAtTheEnds() {
        #expect(LiquidPlayerPolicy.stepped(.player, larger: true) == .expanded)
        #expect(LiquidPlayerPolicy.stepped(.expanded, larger: true) == .expanded)
        #expect(LiquidPlayerPolicy.stepped(.player, larger: false) == .mini)
        #expect(LiquidPlayerPolicy.stepped(.mini, larger: false) == .mini)
    }

    @Test func layoutFollowsHeightAndWidthInterpolates() {
        #expect(LiquidPlayerPolicy.layout(forHeight: 58) == .mini)
        #expect(LiquidPlayerPolicy.layout(forHeight: 172) == .player)
        #expect(LiquidPlayerPolicy.layout(forHeight: LiquidPlayerPolicy.maxHeight) == .expanded)
        #expect(LiquidPlayerPolicy.width(forHeight: 58) == 300)
        #expect(LiquidPlayerPolicy.width(forHeight: 172) == 340)
        #expect(LiquidPlayerPolicy.width(forHeight: 400) == 340)
    }

    @Test func windowStaysOnScreenAndGrowsUpwardNearTheBottom() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let tall = CGSize(width: 340, height: 520)
        let frame = LiquidPlayerPolicy.frame(topLeft: CGPoint(x: 1400, y: 300), size: tall, in: screen)
        #expect(frame.maxX <= screen.maxX && frame.minY >= screen.minY)
        #expect(frame.height == 520)
        let roomy = LiquidPlayerPolicy.frame(topLeft: CGPoint(x: 100, y: 800), size: tall, in: screen)
        #expect(roomy.maxY == 800 && roomy.minX == 100)
    }

    @Test func onlyAClearDownwardPullPopsTheNotchPlayerOut() {
        #expect(LiquidPlayerPolicy.shouldPopOut(translation: CGSize(width: 4, height: 60), enabled: true))
        #expect(!LiquidPlayerPolicy.shouldPopOut(translation: CGSize(width: 4, height: 60), enabled: false))
        #expect(!LiquidPlayerPolicy.shouldPopOut(translation: CGSize(width: 90, height: 50), enabled: true))
        #expect(!LiquidPlayerPolicy.shouldPopOut(translation: CGSize(width: 0, height: 20), enabled: true))
        #expect(!LiquidPlayerPolicy.shouldPopOut(translation: CGSize(width: 0, height: -80), enabled: true))
    }
}

@MainActor
struct StreamIngestTests {
    private func payload(playing: Bool, title: String = "Song", elapsed: TimeInterval = 30, at: Date) -> MediaRemoteStreamMessage {
        .nowPlaying(.init(bundle: "com.apple.Music", title: title, artist: "Artist", album: "Album", duration: 200,
                          elapsed: elapsed, rate: playing ? 1 : 0, timestamp: at, isPlaying: playing, artwork: nil))
    }

    @Test func streamEventUpdatesTheTrackWithoutAnyPollAndKeepsAdvancing() async {
        let provider = StubNowPlayingProvider()
        let model = NowPlayingModel(provider: provider, enabledSources: [.music], stream: nil)
        let anchor = Date()
        model.handleStream(payload(playing: true, at: anchor))
        #expect(model.track?.title == "Song")
        #expect(model.streamAlive)
        #expect(model.track?.stallCap == nil)
        // 60 s later with no further event the elapsed time is still right.
        #expect(abs((model.track?.position(at: anchor.addingTimeInterval(60)) ?? 0) - 90) < 0.01)
    }

    @Test func streamPauseFreezesAndStreamEventsConfirmAnOptimisticTap() async {
        let provider = StubNowPlayingProvider()
        let start = Date()
        var now = start
        let model = NowPlayingModel(provider: provider, enabledSources: [.music], artworkNow: { now }, stream: nil)
        model.handleStream(payload(playing: true, at: start))
        let task = model.command(.playPause)
        #expect(model.track?.isPlaying == false)
        await task?.value
        now = start.addingTimeInterval(0.5)
        model.handleStream(payload(playing: false, elapsed: 31, at: now))
        #expect(model.track?.isPlaying == false)
        #expect(model.track?.snapshot.position == 31)
        #expect(model.track?.position(at: now.addingTimeInterval(30)) == 31)
    }

    @Test func aPollWithoutCoverKeepsTheCoverTheStreamDelivered() async throws {
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 8, bitsPerPixel: 32))
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        let provider = StubNowPlayingProvider()
        await provider.set([NowPlayingSnapshot(source: .music, title: "Song", artist: "Artist", album: "Album",
            duration: 200, position: 31, isPlaying: true)])
        let model = NowPlayingModel(provider: provider, enabledSources: [.music], artworkLoader: { _ in nil }, stream: nil)
        model.handleStream(.nowPlaying(.init(bundle: "com.apple.Music", title: "Song", artist: "Artist", album: "Album",
            duration: 200, elapsed: 30, rate: 1, timestamp: Date(), isPlaying: true, artwork: png)))
        for _ in 0..<100 where model.track?.artwork == nil { try await Task.sleep(for: .milliseconds(10)) }
        #expect(model.track?.artwork != nil)
        await model.refreshNow()
        try await Task.sleep(for: .milliseconds(100))
        #expect(model.track?.artwork != nil)
        model.stop()
    }

    /// Seen live: the YouTube app's accessibility tree named the previous song for a whole track while
    /// MediaRemote had the right one. A lagging poll must not put the old song back on the island.
    @Test func aLaggingYouTubeAppPollDoesNotReplaceTheStreamsSong() async throws {
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 8, bitsPerPixel: 32))
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        let provider = StubNowPlayingProvider()
        await provider.set([NowPlayingSnapshot(source: .youtubeApp, title: "Next", artist: "The Weeknd", album: "",
            duration: 288, position: 40, isPlaying: true)])
        let model = NowPlayingModel(provider: provider, enabledSources: [.youtubeApp], artworkLoader: { _ in nil },
                                    stream: nil)
        model.handleStream(.nowPlaying(.init(bundle: NowPlayingSource.youtubeApp.bundleID, title: "As You Are",
            artist: "The Weeknd", album: "", duration: 340, elapsed: 5, rate: 1, timestamp: Date(), isPlaying: true,
            artwork: png)))
        #expect(model.track?.title == "As You Are")
        await model.refreshNow()
        #expect(model.track?.title == "As You Are")
        model.stop()
    }

    @Test func unknownAppsAreIgnoredByTheStreamMapping() {
        let model = NowPlayingModel(provider: StubNowPlayingProvider(), enabledSources: [.music], stream: nil)
        model.handleStream(.nowPlaying(.init(bundle: "company.thebrowser.Browser", title: "Video", artist: "", album: "",
            duration: 10, elapsed: 1, rate: 1, timestamp: Date(), isPlaying: true, artwork: nil)))
        #expect(model.track == nil)
    }
}
