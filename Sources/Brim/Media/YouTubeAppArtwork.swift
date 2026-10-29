import Foundation
import os

/// The YouTube Music app's cover when its accessibility tree has none: the app exposes no images,
/// and only a watch page's address carries the video id, so on a playlist or home page the playing
/// song had no cover. The page's Media Session metadata always names it. Needs Chrome's
/// "Allow JavaScript from Apple Events"; asked once per song, and not again for a while after a refusal.
/// Right after a track change the page can still describe the previous song, so a miss is retried
/// briefly and only remembered for `retryAfterMiss` (a remembered miss left songs without a cover).
enum YouTubeAppArtwork {
    static let retryAfterRefusal: TimeInterval = 30
    static let retryAfterMiss: TimeInterval = 8
    static let attempts = 3
    static let attemptGap: Duration = .milliseconds(700)

    private struct State {
        var title = ""
        var url: String?
        var checkedAt: Date?
        var refusedAt: Date?
    }
    private static let state = OSAllocatedUnfairLock(initialState: State())
    private static let log = Logger(subsystem: "io.github.cezarprox.brim", category: "artwork")

    /// The Media Session's largest artwork when it describes `title`; single quotes only for AppleScript.
    static func script(title: String) throws -> String {
        let encoded = try JSONEncoder().encode(["title": title]).base64EncodedString()
        return """
        (() => { \(YouTubeMusicQueueReader.pageGuard) \
        const want = JSON.parse(new TextDecoder().decode(Uint8Array.from(atob('\(encoded)'), (c) => c.charCodeAt(0)))); \
        const meta = navigator.mediaSession && navigator.mediaSession.metadata; \
        if (!meta || (meta.title || '').trim() !== want.title.trim()) return 'null'; \
        const art = Array.from(meta.artwork || []); const best = art[art.length - 1]; \
        return (best && best.src) || 'null'; })()
        """
    }

    static func url(for title: String, now: Date = .now) async -> String? {
        let cached = state.withLock { state -> (hit: Bool, url: String?) in
            if state.title == title, state.url != nil
                || state.checkedAt.map({ now.timeIntervalSince($0) < retryAfterMiss }) == true {
                return (true, state.url)
            }
            if let refused = state.refusedAt, now.timeIntervalSince(refused) < retryAfterRefusal { return (true, nil) }
            return (false, nil)
        }
        if cached.hit { return cached.url }
        do {
            var found: String?
            for attempt in 1...attempts where found == nil {
                if attempt > 1 { try await Task.sleep(for: attemptGap) }
                let output = try await MusicQueueReader.run(YouTubeMusicQueueReader.browserScript(
                    for: .youtubeApp, javaScript: try script(title: title)))
                found = output.split(whereSeparator: \.isNewline).map(String.init)
                    .first { NowPlayingSnapshot.safeArtworkURL($0) != nil }
            }
            state.withLock { $0 = State(title: title, url: found, checkedAt: now, refusedAt: nil) }
            log.notice("YouTube app cover: \(found == nil ? "none on the page" : "found", privacy: .public)")
            return found
        } catch {
            log.error("YouTube app cover failed: \(error.localizedDescription, privacy: .public)")
            state.withLock { $0.refusedAt = now }
            return nil
        }
    }
}

extension NowPlayingSnapshot {
    /// The same sample with `url` as its cover.
    func withArtworkURL(_ url: String?) -> NowPlayingSnapshot {
        var copy = NowPlayingSnapshot(source: source, title: title, artist: artist, album: album, duration: duration,
                                      position: position, isPlaying: isPlaying, artworkData: artworkData,
                                      artworkURL: url, albumURL: albumURL, isFavorite: isFavorite, isShuffling: isShuffling)
        copy.pageURL = pageURL
        copy.playbackRate = playbackRate
        copy.repeatMode = repeatMode
        return copy
    }
}
