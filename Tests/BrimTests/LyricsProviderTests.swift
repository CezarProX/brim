import Foundation
import Testing

@testable import Brim

struct LyricsProviderTests {
  private let query = LyricsProvider.Query(title: "Song & Co", artist: "The Artist", album: "Album", duration: 200.4)

  @Test func getURLIsHTTPSLRCLIBWithEncodedQuery() throws {
    let url = try #require(LyricsProvider.getURL(query))
    #expect(url.scheme == "https" && url.host == "lrclib.net" && url.path == "/api/get")
    let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    #expect(items.first { $0.name == "track_name" }?.value == "Song & Co")
    #expect(items.first { $0.name == "duration" }?.value == "200")
    #expect(!url.absoluteString.contains("Song & Co"))
  }

  @Test func emptyAlbumIsOmitted() throws {
    let url = try #require(LyricsProvider.getURL(.init(title: "T", artist: "A", album: "", duration: 10)))
    #expect(!url.absoluteString.contains("album_name"))
  }

  @Test func parsesGetResponseAndRejectsInstrumentalOrEmpty() {
    let ok = #"{"syncedLyrics":"[00:01.00]Hi","plainLyrics":"Hi","instrumental":false}"#
    #expect(LyricsProvider.syncedLyrics(from: Data(ok.utf8), near: 10) == "[00:01.00]Hi")
    let instrumental = #"{"syncedLyrics":"[00:01.00]Hi","instrumental":true}"#
    #expect(LyricsProvider.syncedLyrics(from: Data(instrumental.utf8), near: 10) == nil)
    #expect(LyricsProvider.syncedLyrics(from: Data(#"{"syncedLyrics":"  "}"#.utf8), near: 10) == nil)
    #expect(LyricsProvider.syncedLyrics(from: Data(), near: 10) == nil)
    #expect(LyricsProvider.syncedLyrics(from: Data("garbage".utf8), near: 10) == nil)
  }

  @Test func searchPicksClosestDurationWithSyncedLyrics() {
    let json = #"[{"syncedLyrics":null,"duration":200},{"syncedLyrics":"[00:01.00]far","duration":300},{"syncedLyrics":"[00:01.00]near","duration":203}]"#
    #expect(LyricsProvider.syncedLyrics(from: Data(json.utf8), near: 200) == "[00:01.00]near")
  }

  @Test func searchRejectsADifferentLengthRecording() {
    let json = #"[{"syncedLyrics":"[00:01.00]remix","duration":260}]"#
    #expect(LyricsProvider.syncedLyrics(from: Data(json.utf8), near: 200) == nil)
  }

  @Test func fallsBackToSearchWhenGetFindsNothing() async {
    let provider = LyricsProvider { url in
      url.path == "/api/get" ? Data() : Data(#"[{"syncedLyrics":"[00:02.00]found","duration":200}]"#.utf8)
    }
    #expect(await provider.lyrics(for: query) == "[00:02.00]found")
  }

  @Test func networkFailureIsQuiet() async {
    let provider = LyricsProvider { _ in throw URLError(.timedOut) }
    #expect(await provider.lyrics(for: query) == nil)
  }

  /// YouTube Music in Romanian joins artists with "și"; LRCLIB files the song under the first one.
  @Test func localizedArtistListsFallBackToTheLeadArtist() async {
    let localized = LyricsProvider.Query(title: "Too Many Nights", artist: "Metro Boomin și Future",
                                         album: "HEROES & VILLAINS", duration: 199.92)
    let provider = LyricsProvider { url in
      let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
      let artist = items.first { $0.name == "artist_name" }?.value
      return artist == "Metro Boomin" && url.path == "/api/get"
        ? Data(#"{"syncedLyrics":"[00:01.00]nights","duration":200}"#.utf8) : Data()
    }
    #expect(await provider.lyrics(for: localized) == "[00:01.00]nights")
  }

  @Test func leadArtistSplitsEveryJoiner() {
    for artist in ["A și B", "A & B", "A, B", "A and B", "A x B", "A feat. B", "A ft. B", "A · B", "A, B și C"] {
      #expect(LyricsProvider.leadArtist(artist) == "A", "\(artist)")
    }
    #expect(LyricsProvider.leadArtist("Simon & Garfunkel") == "Simon")
    #expect(LyricsProvider.leadArtist("Solo") == nil)
  }

  @Test func aBusyServerIsAFailureNotAMiss() async {
    let busy = LyricsProvider { _ in throw URLError(.badServerResponse) }
    #expect(await busy.lookup(query) == .failed)
    let none = LyricsProvider { _ in Data() }
    #expect(await none.lookup(query) == .missing)
  }
}

@MainActor
struct LyricsModelRetryTests {
  private let track = NowPlayingTrack(
    snapshot: NowPlayingSnapshot(source: .music, title: "Song", artist: "Artist", album: "Album",
                                 duration: 200, position: 10, isPlaying: true),
    artwork: nil, sampledAt: Date(), stallCap: nil, isTransitioning: false)

  @Test func aFailedLookupIsNotRememberedAsNoLyrics() async throws {
    let store = LyricsStore(directory: FileManager.default.temporaryDirectory
      .appendingPathComponent("lyrics-\(UUID().uuidString)"))
    defer { store.clear() }
    let calls = Counter()
    let provider = LyricsProvider { _ in
      if await calls.next() <= 2 { throw URLError(.badServerResponse) }
      return Data(#"{"syncedLyrics":"[00:01.00]back","duration":200}"#.utf8)
    }
    let model = LyricsModel(store: store, provider: provider, retryDelays: [0.05, 0.05])
    model.sync(track: track, enabled: true)
    for _ in 0..<100 where model.state.lyrics == nil { try await Task.sleep(for: .milliseconds(20)) }
    #expect(model.state.lyrics?.lines.first?.text == "back")
    let key = LyricsStore.key(title: "Song", artist: "Artist", album: "Album", duration: 200)
    #expect(store.load(key: key)?.synced == "[00:01.00]back")
  }

  @Test func aServerThatStaysDownLeavesNothingCached() async throws {
    let store = LyricsStore(directory: FileManager.default.temporaryDirectory
      .appendingPathComponent("lyrics-\(UUID().uuidString)"))
    defer { store.clear() }
    let model = LyricsModel(store: store, provider: LyricsProvider { _ in throw URLError(.timedOut) },
                            retryDelays: [0.01])
    model.sync(track: track, enabled: true)
    for _ in 0..<100 where model.state == .loading { try await Task.sleep(for: .milliseconds(20)) }
    #expect(model.state == .none)
    #expect(store.load(key: LyricsStore.key(title: "Song", artist: "Artist", album: "Album", duration: 200)) == nil)
  }
}

private actor Counter {
  private var value = 0
  func next() -> Int { value += 1; return value }
}

struct LyricsStoreTests {
  private func store() -> LyricsStore {
    LyricsStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("lyrics-\(UUID().uuidString)"))
  }

  @Test func keyIsStableAndCaseInsensitive() {
    let a = LyricsStore.key(title: "Song", artist: "Art", album: "Alb", duration: 200.2)
    #expect(a == LyricsStore.key(title: " song ", artist: "ART", album: "alb", duration: 199.8))
    #expect(a != LyricsStore.key(title: "Other", artist: "Art", album: "Alb", duration: 200))
  }

  @Test func roundTripsHitsAndMisses() {
    let s = store()
    defer { s.clear() }
    s.save(.init(synced: "[00:01.00]x", fetchedAt: .now), key: "hit")
    s.save(.init(synced: nil, fetchedAt: .now), key: "miss")
    #expect(s.load(key: "hit")?.synced == "[00:01.00]x")
    #expect(s.load(key: "miss") != nil)
    #expect(s.load(key: "absent") == nil)
  }

  @Test func staleMissesExpire() {
    let s = store()
    defer { s.clear() }
    s.save(.init(synced: nil, fetchedAt: .now.addingTimeInterval(-8 * 24 * 3600)), key: "old")
    #expect(s.load(key: "old") == nil)
  }

  @Test func pruneKeepsOnlyTheNewest() throws {
    let s = store()
    defer { s.clear() }
    for index in 0..<8 {
      s.save(.init(synced: "x", fetchedAt: .now), key: "k\(index)")
      let url = s.directory.appendingPathComponent("k\(index).json")
      try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: Double(index))], ofItemAtPath: url.path)
    }
    s.prune(limit: 3)
    let left = try FileManager.default.contentsOfDirectory(atPath: s.directory.path).sorted()
    #expect(left == ["k5.json", "k6.json", "k7.json"])
  }
}
