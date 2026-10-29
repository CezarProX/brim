import Foundation
import Testing

@testable import Brim

struct NowPlayingNavigationTests {
    private func song(_ source: NowPlayingSource = .youtubeApp) -> NowPlayingSnapshot {
        NowPlayingSnapshot(source: source, title: "Chicago", artist: "Michael Jackson", album: "Xscape",
                           duration: 240, position: 20, isPlaying: true)
    }

    @Test func youtubeTrackAndArtistOpenTheirExactSourceURLs() throws {
        var snapshot = song()
        snapshot.pageURL = "https://music.youtube.com/watch?v=5KRM9707tyA&si=tracking"
        snapshot.artistURL = "https://music.youtube.com/channel/UC5OrDvL9DscpcAstz7JnQGA?feature=share"
        let track = NowPlayingNavigation.request(for: snapshot, target: .track)
        let artist = NowPlayingNavigation.request(for: snapshot, target: .artist)
        #expect(track.url?.absoluteString == "https://music.youtube.com/watch?v=5KRM9707tyA")
        #expect(artist.url?.absoluteString == "https://music.youtube.com/channel/UC5OrDvL9DscpcAstz7JnQGA")
        #expect(track.source == .youtubeApp && artist.source == .youtubeApp)
        #expect(!artist.isSearchFallback)
    }

    @Test func spotifyTrackURIIsValidatedAndPreserved() {
        var snapshot = song(.spotify)
        snapshot.pageURL = "spotify:track:6rqhFgbbKwnb9MLmUQDhG6"
        #expect(NowPlayingNavigation.request(for: snapshot, target: .track).url?.absoluteString == snapshot.pageURL)
        #expect(NowPlayingNavigation.safeTrackURL("https://open.spotify.com/track/6rqhFgbbKwnb9MLmUQDhG6?si=tracking", source: .spotify)?.absoluteString == snapshot.pageURL)
    }

    @Test func metadataCannotLaunchAnotherServiceOrExecutable() {
        let hostile = ["file:///tmp/a.app", "javascript:alert(1)", "spotify:track:bad", "https://music.youtube.com.evil.test/channel/UC1234567890123456789012", "https://user:pass@music.youtube.com/channel/UC1234567890123456789012", "https://music.youtube.com:444/channel/UC1234567890123456789012", "https://music.youtube.com/browse/MPRE1234567890"]
        for raw in hostile {
            #expect(NowPlayingNavigation.safeArtistURL(raw, source: .youtubeApp) == nil)
        }
        #expect(NowPlayingNavigation.safeTrackURL("spotify:track:6rqhFgbbKwnb9MLmUQDhG6", source: .youtubeApp) == nil)
        #expect(NowPlayingNavigation.safeArtistURL("https://music.youtube.com/channel/UC1234567890123456789012", source: .spotify) == nil)
    }

    @Test func missingArtistIDUsesAnExplicitSourceSpecificSearch() throws {
        for source in NowPlayingSource.allCases {
            var snapshot = song(source)
            snapshot = NowPlayingSnapshot(source: source, title: snapshot.title, artist: "AC/DC & Beyoncé + 'X'", album: "",
                                          duration: 1, position: 0, isPlaying: true)
            let request = NowPlayingNavigation.request(for: snapshot, target: .artist)
            #expect(request.isSearchFallback)
            #expect(request.source == source)
            let url = try #require(request.url)
            if source == .spotify { #expect(url.scheme == "spotify") }
            else {
                let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
                #expect(components.queryItems?.first?.value == snapshot.artist)
                #expect(url.host == (source == .music ? "music.apple.com" : "music.youtube.com"))
            }
        }
    }

    @Test func urlsSurviveArtworkAndPlaybackCopies() {
        var snapshot = song()
        snapshot.pageURL = "https://music.youtube.com/watch?v=5KRM9707tyA"
        snapshot.artistURL = "https://music.youtube.com/channel/UC5OrDvL9DscpcAstz7JnQGA"
        for copy in [snapshot.replacing(isPlaying: false), snapshot.withArtworkURL(nil)] {
            #expect(copy.pageURL == snapshot.pageURL)
            #expect(copy.artistURL == snapshot.artistURL)
        }
    }

    @Test func streamedNavigationMetadataIsClearedWhenSongChanges() {
        var previous = song()
        previous.pageURL = "https://music.youtube.com/watch?v=5KRM9707tyA"
        previous.artistURL = "https://music.youtube.com/channel/UC5OrDvL9DscpcAstz7JnQGA"
        var payload = MediaRemoteStreamMessage.Payload(bundle: previous.source.bundleID, title: previous.title,
            artist: previous.artist, album: previous.album, duration: 240, elapsed: 30, rate: 1,
            timestamp: .now, isPlaying: true, artwork: nil)
        let same = payload.snapshot(source: .youtubeApp, previous: previous)
        #expect(same.pageURL == previous.pageURL && same.artistURL == previous.artistURL)
        payload.title = "A different song"
        let changed = payload.snapshot(source: .youtubeApp, previous: previous)
        #expect(changed.pageURL == nil && changed.artistURL == nil)
    }

    @Test func browserMetadataKeepsOnlySafeNavigationURLs() throws {
        let json = #"{"title":"Chicago","artist":"Michael Jackson","album":"Xscape","duration":240,"position":20,"isPlaying":true,"pageURL":"https://music.youtube.com/watch?v=5KRM9707tyA","artistURL":"https://music.youtube.com/channel/UC5OrDvL9DscpcAstz7JnQGA"}"#
        let snapshot = try #require(try NowPlayingSnapshot.browserJSON(json, source: .youtubeChrome))
        #expect(snapshot.pageURL != nil && snapshot.artistURL != nil)
    }
}

@MainActor
struct NowPlayingNavigationActionTests {
    @Test func trackAndArtistButtonsUseTheDisplayedPlayer() async {
        let snapshot = NowPlayingSnapshot(source: .spotify, title: "Chicago", artist: "Michael Jackson", album: "",
                                          duration: 240, position: 20, isPlaying: true)
        var actions: [NowPlayingNavigation.Target] = []
        let model = NowPlayingModel(provider: NavigationFixture(snapshot: snapshot), enabledSources: [.spotify],
            artworkLoader: { _ in nil }, stream: nil, navigate: { displayed, target in
                #expect(displayed.source == .spotify)
                #expect(displayed.title == "Chicago")
                actions.append(target)
            })
        await model.refreshNow()
        model.openTrack()
        model.openArtist()
        for _ in 0..<10 where actions.count < 2 { await Task.yield() }
        #expect(actions == [.track, .artist])
    }

    @Test func redesignedYoutubeArtistButtonIsSelectedBeforeTheAlbumSeparator() {
        let nodes = [NowPlayingAccessibility.PlayerText(role: "AXGroup", label: "Now playing"),
                     .init(role: "AXStaticText", label: "Chicago"),
                     .init(role: "AXButton", label: "Michael Jackson"),
                     .init(role: "AXStaticText", label: " • "),
                     .init(role: "AXButton", label: "Xscape")]
        #expect(NowPlayingAccessibility.artistNavigationIndex(in: nodes) == 2)
        #expect(NowPlayingAccessibility.artistNavigationIndex(in: [.init(role: "AXButton", label: "Subscribe")]) == nil)
    }
}

private actor NavigationFixture: NowPlayingProviding {
    let snapshot: NowPlayingSnapshot
    init(snapshot: NowPlayingSnapshot) { self.snapshot = snapshot }
    func connect(_ source: NowPlayingSource) async throws {}
    func snapshot(_ source: NowPlayingSource) async throws -> NowPlayingSnapshot? { snapshot }
    func perform(_ command: NowPlayingCommand, expected: NowPlayingSnapshot, token: NowPlayingActionToken) async throws {}
}
