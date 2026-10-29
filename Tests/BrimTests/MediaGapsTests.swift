import Foundation
import Testing

@testable import Brim

struct MediaGapsTests {
  private func snap(_ source: NowPlayingSource = .music, repeatMode: RepeatMode? = nil,
                    favorite: Bool? = nil, shuffle: Bool? = nil) -> NowPlayingSnapshot {
    var value = NowPlayingSnapshot(source: source, title: "T", artist: "A", album: "B", duration: 100,
                                   position: 10, isPlaying: true, isFavorite: favorite, isShuffling: shuffle)
    value.repeatMode = repeatMode
    return value
  }

  // MARK: Repeat

  @Test func repeatCyclesOffAllOneForMusic() {
    #expect(RepeatMode.off.next(supportsOne: true) == .all)
    #expect(RepeatMode.all.next(supportsOne: true) == .one)
    #expect(RepeatMode.one.next(supportsOne: true) == .off)
  }

  @Test func spotifyRepeatSkipsOne() {
    #expect(RepeatMode.off.next(supportsOne: false) == .all)
    #expect(RepeatMode.all.next(supportsOne: false) == .off)
    #expect(RepeatMode.supportsOne(.music))
    #expect(!RepeatMode.supportsOne(.spotify))
  }

  @Test func repeatEventCodesRoundTrip() {
    for mode in RepeatMode.allCases { #expect(RepeatMode(musicCode: mode.musicCode) == mode) }
    #expect(RepeatMode(musicCode: "nope") == nil)
    #expect(NowPlayingAppleEvents.code(RepeatMode.one.musicCode) == NowPlayingAppleEvents.code("kRp1"))
    #expect(NowPlayingAppleEvents.codeString(NowPlayingAppleEvents.code("kAll")) == "kAll")
    #expect(RepeatMode(spotifyRepeating: true) == .all)
    #expect(RepeatMode.one.spotifyRepeating && !RepeatMode.off.spotifyRepeating)
    #expect(RepeatMode.one.symbol == "repeat.1" && RepeatMode.all.symbol == "repeat")
  }

  @Test func repeatOverlayShowsIntentThenConfirms() {
    var overlay = OptimisticPlayback()
    let now = Date()
    overlay.setRepeat(.one, now: now)
    let shown = overlay.apply(to: snap(repeatMode: .off), sampleAnchor: now, now: now)
    #expect(shown.snapshot.repeatMode == .one)
    let events = overlay.reconcile(observed: snap(repeatMode: .one), position: 10, now: now.addingTimeInterval(0.5))
    #expect(events == [.confirmed])
    #expect(overlay.isEmpty)
  }

  @Test func repeatOverlayRollsBackWhenPlayerDisagrees() {
    var overlay = OptimisticPlayback()
    let now = Date()
    overlay.setRepeat(.all, now: now)
    let events = overlay.reconcile(observed: snap(repeatMode: .off), position: 10,
                                   now: now.addingTimeInterval(OptimisticPlayback.grace + 0.1))
    #expect(events == [.rolledBack])
    #expect(overlay.nextDeadline == nil)
  }

  @Test func repeatSurvivesSnapshotCopy() {
    #expect(snap(repeatMode: .all).replacing(isPlaying: false).repeatMode == .all)
    #expect(snap(repeatMode: .all).replacing(repeatMode: .one).repeatMode == .one)
  }

  // MARK: Button slots

  @Test func repeatSlotAppearsOnlyWhenThePlayerReportsIt() {
    typealias Caps = MediaButtonSlots.Capabilities
    #expect(MediaButtonSlots.resolve([.repeat], capabilities: Caps(snapshot: snap(repeatMode: .off), lyricsEnabled: false)) == [.repeat])
    #expect(MediaButtonSlots.resolve([.repeat], capabilities: Caps(snapshot: snap(.music), lyricsEnabled: false)).isEmpty)
  }

  @Test func playlistAndFavoriteAreAppleMusicOnlyAndSpotifyFallsBackToShuffle() {
    typealias Caps = MediaButtonSlots.Capabilities
    let music = Caps(snapshot: snap(.music, favorite: false, shuffle: true), lyricsEnabled: false)
    #expect(MediaButtonSlots.resolve([.favorite, .addToPlaylist], capabilities: music) == [.favorite, .addToPlaylist])
    let spotify = Caps(snapshot: snap(.spotify, repeatMode: .off, shuffle: false), lyricsEnabled: false)
    #expect(MediaButtonSlots.resolve([.addToPlaylist], capabilities: spotify).isEmpty)
    #expect(MediaButtonSlots.resolve([.favorite, .repeat], capabilities: spotify) == [.shuffle, .repeat])
  }

  // MARK: Playlists

  @Test func playlistScriptEscapesQuotesAndBackslashes() {
    #expect(MusicPlaylistScripts.literal(#"Best "of" \ 90s"#) == #"Best \"of\" \\ 90s"#)
    #expect(MusicPlaylistScripts.literal("a\nb\tc") == "a b c")
    let script = MusicPlaylistScripts.addCurrentTrack(to: #"x" & (do shell script "id") & ""#)
    #expect(script == #"tell application "Music" to duplicate current track to user playlist "x\" & (do shell script \"id\") & \"""#)
  }

  @Test func playlistNamesAreCleanedAndCapped() {
    #expect(MusicPlaylistScripts.cleaned([" Chill ", "", "Chill", "Gym", "  "]) == ["Chill", "Gym"])
    #expect(MusicPlaylistScripts.cleaned((0..<100).map(String.init), limit: 5).count == 5)
  }

  @Test func playlistCacheExpires() {
    let now = Date()
    #expect(MusicPlaylistsModel.needsRefresh(loadedAt: nil, now: now))
    #expect(!MusicPlaylistsModel.needsRefresh(loadedAt: now.addingTimeInterval(-10), now: now))
    #expect(MusicPlaylistsModel.needsRefresh(loadedAt: now.addingTimeInterval(-61), now: now))
  }

  @Test func playlistFeedbackSymbols() {
    #expect(PlaylistFeedback.symbol(for: .none) == "text.badge.plus")
    #expect(PlaylistFeedback.symbol(for: .added("X")) == "checkmark.circle.fill")
    #expect(PlaylistFeedback.help(for: .added("Gym")) == "Added to Gym")
  }

  // MARK: Word sweep

  private func line(_ text: String, at time: TimeInterval = 10) -> LyricLine { LyricLine(time: time, text: text, words: []) }

  @Test func synthesizedWordsStartAtLineAndAreMonotonic() {
    let words = LyricWordSynth.words(for: line("Hello darkness my old friend"), nextLineTime: 15)
    #expect(words.count == 5)
    #expect(words.first?.time == 10)
    #expect(zip(words, words.dropFirst()).allSatisfy { $0.time < $1.time })
    #expect(words.map(\.text).joined() == "Hello darkness my old friend")
    #expect((words.last?.time ?? 99) < 15, "the sweep finishes before the next line")
  }

  @Test func longerWordsGetMoreTime() {
    let words = LyricWordSynth.words(for: line("I extraordinarily go"), nextLineTime: 16)
    let short = words[1].time - words[0].time
    let long = words[2].time - words[1].time
    #expect(long > short * 5)
  }

  @Test func fileWordTagsWinOverSynthesis() {
    let tagged = LyricLine(time: 1, text: "a b", words: [LyricWord(time: 1, text: "a "), LyricWord(time: 1.9, text: "b")])
    #expect(LyricWordSynth.words(for: tagged, nextLineTime: 9) == tagged.words)
  }

  @Test func shortLineBeforeLongGapDoesNotCrawl() {
    let words = LyricWordSynth.words(for: line("Oh yeah"), nextLineTime: 60)
    #expect((words.last?.time ?? 99) < 10 + LyricWordSynth.maxSungSeconds)
    #expect((words.last?.time ?? 99) - 10 < 2)
  }

  @Test func lastLineAndEmptyLinesAreSafe() {
    #expect(LyricWordSynth.words(for: line(""), nextLineTime: nil).isEmpty)
    #expect(LyricWordSynth.words(for: line("   "), nextLineTime: nil).isEmpty)
    #expect(LyricWordSynth.words(for: line("one two"), nextLineTime: nil).count == 2)
    #expect(LyricWordSynth.words(for: line("one two"), nextLineTime: 10).count == 2, "zero gap stays finite")
    #expect(LyricWordSynth.words(for: line("one two"), nextLineTime: .nan).allSatisfy { $0.time.isFinite })
  }

  @Test func activeIndexFollowsTime() {
    let words = LyricWordSynth.words(for: line("aa bb cc"), nextLineTime: 14)
    #expect(LyricWordSynth.activeIndex(in: words, at: 9.9) == nil)
    #expect(LyricWordSynth.activeIndex(in: words, at: 10) == 0)
    #expect(LyricWordSynth.activeIndex(in: words, at: 13.9) == 2)
    #expect(LyricWordSynth.activeIndex(in: words, at: .nan) == nil)
  }

  @Test func timedLyricsSweepsPlainLRC() {
    let lyrics = LRCParser.parse("[00:01.00]Hello there world\n[00:05.00]Second line")
    #expect(!lyrics.hasWordTiming)
    #expect(lyrics.sweepWords(at: 0).count == 3)
    #expect(lyrics.sweepWords(at: 1).count == 2)
    #expect(lyrics.sweepWords(at: 7).isEmpty)
  }

  // MARK: Ken Burns, badge, panels

  @Test func kenBurnsStaysInsideTheCoveredBounds() {
    for step in stride(from: 0.0, through: 200, by: 0.7) {
      let f = KenBurns.frame(at: step, seed: 0.37)
      #expect(f.scale >= 1.04 && f.scale <= KenBurns.maxScale)
      #expect(abs(f.offsetX) <= (f.scale - 1) / 2 + 1e-9 && abs(f.offsetY) <= (f.scale - 1) / 2 + 1e-9)
    }
    #expect(KenBurns.frame(at: .infinity).scale > 1)
  }

  @Test func kenBurnsLoopsSeamlesslyAndVariesPerSong() {
    let a = KenBurns.frame(at: 3, seed: 0.1)
    let b = KenBurns.frame(at: 3 + KenBurns.period, seed: 0.1)
    #expect(abs(a.scale - b.scale) < 1e-6 && abs(a.offsetX - b.offsetX) < 1e-6)
    #expect(KenBurns.phase(for: "Song A") == KenBurns.phase(for: "Song A"))
    #expect(KenBurns.phase(for: "Song A") != KenBurns.phase(for: "Song B"))
    #expect((0..<1).contains(KenBurns.phase(for: "x")))
  }

  @Test func lyricsBadgeNeedsFeatureAndLyrics() {
    let ready = LyricsModel.State.ready(LRCParser.parse("[00:01.00]hi"))
    #expect(LyricsBadge.isVisible(enabled: true, state: ready))
    #expect(!LyricsBadge.isVisible(enabled: false, state: ready))
    #expect(!LyricsBadge.isVisible(enabled: true, state: .none))
    #expect(!LyricsBadge.isVisible(enabled: true, state: .loading))
  }

  @Test func floatingLyricsPanelChoice() {
    #expect(LiquidPlayerPanel.lyricsPanel(floating: true) == .floatingLyrics)
    #expect(LiquidPlayerPanel.lyricsPanel(floating: false) == .lyrics)
    #expect(LiquidPlayerPanel.floatingLyrics.isLyrics && LiquidPlayerPanel.lyrics.isLyrics)
    #expect(!LiquidPlayerPanel.queue.isLyrics && !LiquidPlayerPanel.cover.isLyrics)
  }
}

struct MediaGapsSafetyTests {
  @Test func testsNeverDriveTheRealMusicApp() {
    #expect(!MusicPlaylistsModel.canRun)
  }
}
