import AppKit

// These are adapters with real metadata sources; unsupported players never show sample data.
enum NowPlayingSource: String, CaseIterable, Codable, Sendable, Identifiable {
    case music, spotify, youtubeChrome, youtubeSafari, youtubeApp
    /// The installed YouTube Music web app (a Chrome app shim).
    static let youtubeAppID = "cinhimbnkkaeohfgghhklpknlkffjgod"
    var id: String { rawValue }
    var name: String {
        switch self {
        case .music: return "Apple Music"
        case .spotify: return "Spotify"
        case .youtubeChrome: return "YouTube Music · Chrome"
        case .youtubeSafari: return "YouTube Music · Safari"
        case .youtubeApp: return "YouTube Music app"
        }
    }
    var bundleID: String {
        switch self {
        case .music: return "com.apple.Music"
        case .spotify: return "com.spotify.client"
        case .youtubeChrome: return "com.google.Chrome"
        case .youtubeSafari: return "com.apple.Safari"
        case .youtubeApp: return "com.google.Chrome.app.cinhimbnkkaeohfgghhklpknlkffjgod"
        }
    }
    var isBrowser: Bool { self == .youtubeChrome || self == .youtubeSafari }
}

enum NowPlayingCommand: Sendable {
    case playPause, next, previous, seek(TimeInterval)
    /// Apple Music only: the track's favorite heart/star.
    case setFavorite(Bool)
    case setShuffle(Bool)
    /// Apple Music (off/one/all) and Spotify (off/all).
    case setRepeat(RepeatMode)
}

/// The worker checks this immediately before an external action, not just on UI completion.
final class NowPlayingActionToken: @unchecked Sendable {
    private let lock = NSLock()
    private var valid = true
    var isValid: Bool { lock.lock(); defer { lock.unlock() }; return valid }
    func invalidate() { lock.lock(); valid = false; lock.unlock() }
}

enum NowPlayingFailure: Error, LocalizedError, Sendable {
    case notRunning(String), permission(String), accessibility, unavailable(String), timeout
    var errorDescription: String? {
        switch self {
        case .notRunning(let name): return "Open \(name) and start a song, then connect."
        case .permission(let name): return "Allow Brim to control \(name) in System Settings → Privacy & Security → Automation."
        case .accessibility: return "Allow Brim in System Settings → Privacy & Security → Accessibility to show YouTube Music automatically."
        case .unavailable(let message): return message
        case .timeout: return "The player did not respond. Try again in a moment."
        }
    }
}

struct NowPlayingSnapshot: Sendable, Equatable {
    let source: NowPlayingSource
    let title: String
    let artist: String
    let album: String
    let duration: TimeInterval
    let position: TimeInterval
    let isPlaying: Bool
    let artworkData: Data?
    let artworkURL: String?
    let albumURL: String?
    /// nil when the player doesn't expose it.
    let isFavorite: Bool?
    let isShuffling: Bool?
    /// A validated source-specific track link; YouTube keeps its watch page and playlist.
    var pageURL: String?
    /// The real artist page when the player exposes one; absent IDs use a service search.
    var artistURL: String?
    /// 1 while playing at normal speed, 0 paused; MediaRemote reports it with the elapsed time.
    var playbackRate: Double = 1
    /// nil when the player doesn't expose repeat (YouTube Music).
    var repeatMode: RepeatMode?

    init(source: NowPlayingSource, title: String, artist: String, album: String,
         duration: TimeInterval, position: TimeInterval, isPlaying: Bool,
         artworkData: Data? = nil, artworkURL: String? = nil, albumURL: String? = nil,
         isFavorite: Bool? = nil, isShuffling: Bool? = nil) {
        self.isFavorite = isFavorite
        self.isShuffling = isShuffling
        self.source = source
        self.title = String(title.prefix(2048))
        self.artist = String(artist.prefix(2048))
        self.album = String(album.prefix(2048))
        self.duration = duration.isFinite ? max(0, duration) : 0
        self.position = position.isFinite ? min(max(0, position), self.duration > 0 ? self.duration : .greatestFiniteMagnitude) : 0
        self.isPlaying = isPlaying
        self.artworkData = artworkData
        self.artworkURL = artworkURL
        self.albumURL = albumURL
    }

    static func safeArtworkURL(_ value: String) -> URL? {
        guard let url = URL(string: value), url.scheme == "https", url.user == nil,
              url.password == nil, url.port == nil,
              let host = url.host?.lowercased(),
              ["i.scdn.co", "lh3.googleusercontent.com", "yt3.googleusercontent.com", "i.ytimg.com", "yt3.ggpht.com"].contains(host) else { return nil }
        return url
    }

    static func safeAlbumURL(_ value: String) -> URL? {
        guard let url = URL(string: value), url.scheme == "https", url.host == "music.youtube.com",
              url.user == nil, url.password == nil, url.port == nil else { return nil }
        let identifier = url.lastPathComponent
        if url.path == "/browse/\(identifier)", identifier.range(of: #"^MPRE[A-Za-z0-9_-]{3,120}$"#, options: .regularExpression) != nil {
            return URL(string: "https://music.youtube.com/browse/\(identifier)")
        }
        if url.path == "/playlist", let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let playlist = components.queryItems?.first(where: { $0.name == "list" })?.value,
           playlist.range(of: #"^OLAK5uy[A-Za-z0-9_-]{3,120}$"#, options: .regularExpression) != nil {
            return URL(string: "https://music.youtube.com/playlist?list=\(playlist)")
        }
        return nil
    }

    static func browserJSON(_ json: String, source: NowPlayingSource) throws -> Self? {
        guard json.utf8.count < 32_768 else { throw NowPlayingFailure.unavailable("Player metadata is too large.") }
        struct Metadata: Decodable {
            let title: String
            let artist: String
            let album: String
            let duration: Double
            let position: Double
            let isPlaying: Bool
            let artworkURL: String?
            let pageURL: String?
            let artistURL: String?
        }
        guard let metadata = try JSONDecoder().decode(Metadata?.self, from: Data(json.utf8)),
              !metadata.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        var snapshot = Self(source: source, title: metadata.title, artist: metadata.artist, album: metadata.album,
                            duration: metadata.duration, position: metadata.position, isPlaying: metadata.isPlaying,
                            artworkURL: metadata.artworkURL)
        snapshot.pageURL = metadata.pageURL.flatMap { NowPlayingNavigation.safeTrackURL($0, source: source)?.absoluteString }
        snapshot.artistURL = metadata.artistURL.flatMap { NowPlayingNavigation.safeArtistURL($0, source: source)?.absoluteString }
        return snapshot
    }
}

struct NowPlayingTrack {
    let snapshot: NowPlayingSnapshot
    let artwork: NSImage?
    /// When `snapshot.position` was true: the anchor of the elapsed-time clock.
    var sampledAt: Date = Date()
    /// Polled sources may stall, so extrapolation stops after this long; streamed ones set nil.
    var stallCap: TimeInterval? = 3
    /// A next/previous is in flight: the UI shows a skeleton until the new song arrives.
    var isTransitioning = false

    var clock: ElapsedClock {
        ElapsedClock(position: snapshot.position, anchor: sampledAt,
                     rate: isPlaying ? max(0, snapshot.playbackRate == 0 ? 1 : snapshot.playbackRate) : 0,
                     duration: duration, stallCap: stallCap)
    }

    func position(at date: Date) -> TimeInterval { clock.position(at: date) }

    var title: String { snapshot.title }
    var artist: String { snapshot.artist }
    var album: String { snapshot.album }
    var duration: TimeInterval { snapshot.duration }
    var position: TimeInterval { snapshot.position }
    var isPlaying: Bool { snapshot.isPlaying }
    var sourceName: String { snapshot.source.name }
}

protocol NowPlayingProviding: Sendable {
    func runningSources() async -> [NowPlayingSource]
    func connect(_ source: NowPlayingSource) async throws
    func snapshot(_ source: NowPlayingSource) async throws -> NowPlayingSnapshot?
    func perform(_ command: NowPlayingCommand, expected: NowPlayingSnapshot, token: NowPlayingActionToken) async throws
}

extension NowPlayingProviding {
    func runningSources() async -> [NowPlayingSource] { [] }
}
