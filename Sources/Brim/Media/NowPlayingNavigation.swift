import AppKit

/// Destinations are built from allowlisted service links, never from executable or arbitrary URLs.
/// Some native players expose only an artist name: that fallback is explicitly a service search.
enum NowPlayingNavigation {
    enum Target: Equatable, Sendable { case track, artist }
    struct Request {
        let source: NowPlayingSource
        let url: URL?
        let isSearchFallback: Bool
    }

    static func request(for snapshot: NowPlayingSnapshot, target: Target) -> Request {
        switch target {
        case .track:
            return Request(source: snapshot.source,
                           url: snapshot.pageURL.flatMap { safeTrackURL($0, source: snapshot.source) }, isSearchFallback: false)
        case .artist:
            if let url = snapshot.artistURL.flatMap({ safeArtistURL($0, source: snapshot.source) }) {
                return Request(source: snapshot.source, url: url, isSearchFallback: false)
            }
            let artist = snapshot.artist.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !artist.isEmpty else { return Request(source: snapshot.source, url: nil, isSearchFallback: false) }
            return Request(source: snapshot.source, url: searchURL(artist, source: snapshot.source), isSearchFallback: true)
        }
    }

    static func safeTrackURL(_ raw: String, source: NowPlayingSource) -> URL? {
        switch source {
        case .youtubeApp, .youtubeChrome, .youtubeSafari:
            guard safeHTTPS(raw, host: "music.youtube.com") != nil,
                  let value = NowPlayingResume.sanitizedPage(raw) else { return nil }
            return URL(string: value)
        case .spotify: return spotifyURL(raw, kind: "track")
        case .music: return appleMusicURL(raw, artist: false)
        }
    }

    static func safeArtistURL(_ raw: String, source: NowPlayingSource) -> URL? {
        switch source {
        case .youtubeApp, .youtubeChrome, .youtubeSafari:
            guard let parts = safeHTTPS(raw, host: "music.youtube.com"),
                  parts.path.range(of: #"^/(channel|browse)/UC[A-Za-z0-9_-]{10,120}$"#, options: .regularExpression) != nil
            else { return nil }
            return URL(string: "https://music.youtube.com" + parts.path)
        case .spotify: return spotifyURL(raw, kind: "artist")
        case .music: return appleMusicURL(raw, artist: true)
        }
    }

    private static func safeHTTPS(_ raw: String, host: String) -> URLComponents? {
        guard raw.utf8.count <= 4096, let parts = URLComponents(string: raw), parts.scheme == "https",
              parts.host == host, parts.user == nil, parts.password == nil, parts.port == nil else { return nil }
        return parts
    }

    private static func spotifyURL(_ raw: String, kind: String) -> URL? {
        guard raw.utf8.count <= 4096 else { return nil }
        let prefix = "spotify:\(kind):"
        let identifier: String
        if raw.hasPrefix(prefix) {
            identifier = String(raw.dropFirst(prefix.count))
        } else {
            guard let parts = safeHTTPS(raw, host: "open.spotify.com") else { return nil }
            let path = parts.path.split(separator: "/")
            guard path.count == 2, path[0] == Substring(kind) else { return nil }
            identifier = String(path[1])
        }
        guard identifier.count == 22, identifier.range(of: #"^[A-Za-z0-9]{22}$"#, options: .regularExpression) != nil else { return nil }
        return URL(string: prefix + identifier)
    }

    private static func appleMusicURL(_ raw: String, artist: Bool) -> URL? {
        guard var parts = safeHTTPS(raw, host: "music.apple.com") else { return nil }
        let path = parts.path.split(separator: "/")
        guard (3...4).contains(path.count), path[0].range(of: #"^[a-z]{2}$"#, options: .regularExpression) != nil,
              (artist ? path[1] == "artist" : ["song", "album"].contains(String(path[1]))),
              path.last?.range(of: #"^[0-9]{1,24}$"#, options: .regularExpression) != nil else { return nil }
        parts.fragment = nil
        parts.queryItems = artist ? nil : parts.queryItems?.filter {
            $0.name == "i" && $0.value?.range(of: #"^[0-9]{1,24}$"#, options: .regularExpression) != nil
        }
        return parts.url
    }

    private static func searchURL(_ term: String, source: NowPlayingSource) -> URL? {
        if source == .spotify {
            let unreserved = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
            guard let query = ("artist:" + term).addingPercentEncoding(withAllowedCharacters: unreserved) else { return nil }
            return URL(string: "spotify:search:" + query)
        }
        var parts = URLComponents()
        parts.scheme = "https"
        parts.host = source == .music ? "music.apple.com" : "music.youtube.com"
        parts.path = "/search"
        parts.queryItems = [URLQueryItem(name: source == .music ? "term" : "q", value: term)]
        return parts.url
    }

    @MainActor static func open(_ snapshot: NowPlayingSnapshot, target: Target) async throws {
        if target == .track, snapshot.source == .music, snapshot.pageURL == nil {
            // Music's own reveal command selects the current track, including local/library songs.
            _ = try? await Task.detached(priority: .userInitiated) {
                let bridge = try NowPlayingAppleEvents(source: .music)
                guard let current = try bridge.nativeSnapshot(), current.title == snapshot.title,
                      current.artist == snapshot.artist else { return }
                _ = try bridge.send(eventClass: "hook", eventID: "Revl", parameters: ["----": NowPlayingAppleEvents.property("pTrk")])
            }.value
        }
        if target == .track, snapshot.source.isBrowser {
            if (try? await Task.detached(priority: .userInitiated, operation: {
                try NowPlayingBrowser.focusPlayingTab(expected: snapshot)
            }).value) == true { activate(snapshot.source); return }
        }
        if target == .artist, snapshot.source == .youtubeApp, snapshot.artistURL == nil {
            if (try? await Task.detached(priority: .userInitiated, operation: {
                try NowPlayingAccessibility.pressArtist(expected: snapshot)
            }).value) == true { activate(snapshot.source); return }
        }
        let destination = request(for: snapshot, target: target)
        guard let url = destination.url else { activate(snapshot.source); return }
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: snapshot.source.bundleID) else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.open([url], withApplicationAt: app, configuration: configuration) { _, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
    }

    @MainActor private static func activate(_ source: NowPlayingSource) {
        NSRunningApplication.runningApplications(withBundleIdentifier: source.bundleID).first?.activate(options: [])
    }
}
