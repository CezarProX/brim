import Foundation
import Testing

@testable import Brim

/// MediaRemote and YouTube Music's page name the same song differently; a poll must not replace
/// the stream's song (and its cover) just because of that.
struct NowPlayingSongMatchTests {
  private let cover = Data([1, 2, 3])

  private func stream(_ title: String = "Zi de Zi", artist: String = "Andrei G și Ministerul Manelelor",
                      duration: TimeInterval = 167.04) -> NowPlayingSnapshot {
    NowPlayingSnapshot(source: .youtubeApp, title: title, artist: artist, album: "Zi de Zi",
                       duration: duration, position: 3, isPlaying: true, artworkData: cover)
  }

  private func poll(_ title: String = "Zi de Zi", artist: String = "Andrei G · Ministerul Manelelor",
                    duration: TimeInterval = 167, source: NowPlayingSource = .youtubeApp) -> NowPlayingSnapshot {
    var snapshot = NowPlayingSnapshot(source: source, title: title, artist: artist, album: "",
                                      duration: duration, position: 9, isPlaying: true,
                                      artworkURL: "https://i.ytimg.com/vi/abc/maxresdefault.jpg")
    snapshot.pageURL = "https://music.youtube.com/watch?v=abc"
    return snapshot
  }

  @Test func differentlySpelledArtistsAreTheSameSong() throws {
    let merged = try #require(NowPlayingSongMatch.merge(poll: poll(), into: stream()))
    #expect(merged.artist == "Andrei G și Ministerul Manelelor")
    #expect(merged.title == "Zi de Zi")
    #expect(merged.artworkData == cover)
    #expect(merged.artworkURL == "https://i.ytimg.com/vi/abc/maxresdefault.jpg")
    #expect(merged.pageURL == "https://music.youtube.com/watch?v=abc")
    #expect(merged.position == 9)
    #expect(merged.album == "Zi de Zi")
  }

  @Test func titleSuffixesStillMatch() {
    let stream = stream("Earned It (Fifty Shades Of Grey)", artist: "The Weeknd", duration: 277)
    let page = poll("Earned It (Fifty Shades Of Grey) [From The Soundtrack]", artist: "The Weeknd", duration: 277)
    #expect(NowPlayingSongMatch.merge(poll: page, into: stream)?.title == "Earned It (Fifty Shades Of Grey)")
    #expect(NowPlayingSongMatch.merge(poll: poll("Earned It", artist: "The Weeknd", duration: 276), into: stream) != nil)
  }

  @Test func aRealSongChangeIsNotMerged() {
    #expect(NowPlayingSongMatch.merge(poll: poll("Altă piesă", artist: "Alt artist", duration: 200), into: stream()) == nil)
    // Same artist, different song of a different length.
    #expect(NowPlayingSongMatch.merge(poll: poll("Altceva", duration: 201), into: stream()) == nil)
    // Same length but nothing else in common.
    #expect(NowPlayingSongMatch.merge(poll: poll("Altceva", artist: "Cineva", duration: 167), into: stream()) == nil)
  }

  @Test func otherAppsAndUnknownLengthsAreNotMerged() {
    #expect(NowPlayingSongMatch.merge(poll: poll(source: .music), into: stream()) == nil)
    #expect(NowPlayingSongMatch.merge(poll: poll(duration: 0), into: stream()) == nil)
  }
}
