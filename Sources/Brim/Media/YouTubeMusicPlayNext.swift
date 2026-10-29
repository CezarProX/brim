import Foundation

/// "Play next" done by YouTube Music itself: the row's action menu is opened on the page and its
/// Play next item chosen, so YouTube's own queue changes and every skip respects it (the island's,
/// the keyboard's, the page's). Needs page scripting, which in Chrome (and the YouTube Music app,
/// a Chrome app window) is View › Developer › Allow JavaScript from Apple Events.
extension YouTubeMusicQueueReader {
    /// Time for the menu popup to render between opening it and choosing from it.
    static let menuSettle: Duration = .milliseconds(350)

    static func playNext(_ item: QueueItem, current snapshot: NowPlayingSnapshot) async throws {
        guard snapshot.source != .music, snapshot.source != .spotify else {
            throw NowPlayingFailure.unavailable("This player has no YouTube Music queue.")
        }
        let opened = try await runInTabs(
            for: snapshot.source, javaScript: try openMenuScript(title: item.title, current: snapshot.title))
        guard lines(opened).contains("opened") else {
            throw NowPlayingFailure.unavailable("The queued song is no longer listed.")
        }
        try await Task.sleep(for: menuSettle)
        let chosen = try await runInTabs(
            for: snapshot.source, javaScript: try choosePlayNextScript(current: snapshot.title))
        guard lines(chosen).contains("ok") else {
            throw NowPlayingFailure.unavailable("YouTube Music did not offer Play next for this song.")
        }
    }

    private static func lines(_ output: String) -> [Substring] { output.split(whereSeparator: \.isNewline) }

    /// Page data reaches the scripts only as base64 JSON, so titles never break out of the string.
    private static func payload(_ values: [String: String]) throws -> String {
        try JSONEncoder().encode(values).base64EncodedString()
    }

    /// Shared prelude: decodes `want` and leaves every tab but the one playing `want.current` alone.
    /// The playing song is the page's media session title or the queue's selected row, matched up to
    /// a featured-artist suffix ("Let Me Love You" / "Let Me Love You (cu Justin Bieber)"). The new
    /// player UI has no `ytmusic-player-bar`, so that is not used (checked on the live app).
    /// Single quotes only, so it embeds in AppleScript unchanged.
    private static func prelude(_ encoded: String) -> String {
        """
        \(pageGuard) \
        const want = JSON.parse(new TextDecoder().decode(Uint8Array.from(atob('\(encoded)'), (c) => c.charCodeAt(0)))); \
        const titleOf = (root) => { const node = root && root.querySelector('.song-title, yt-formatted-string.title'); \
        return ((node && (node.getAttribute('title') || node.textContent)) || '').trim(); }; \
        const same = (a, b) => { a = a.trim().toLowerCase(); b = b.trim().toLowerCase(); \
        return a !== '' && b !== '' && (a === b || [' (', ' ['].some((s) => a.startsWith(b + s) || b.startsWith(a + s))); }; \
        const queue = \(queueItems); \
        const playing = queue.findIndex((row) => row.hasAttribute('selected')); \
        const session = (navigator.mediaSession && navigator.mediaSession.metadata && navigator.mediaSession.metadata.title) || ''; \
        if (!same(session, want.current) && !(playing >= 0 && same(titleOf(queue[playing]), want.current))) return 'other';
        """
    }

    /// Opens the action menu of the first row after the playing song (in the queue, else in the
    /// list on screen) whose title is the pick's.
    static func openMenuScript(title: String, current: String) throws -> String {
        let encoded = try payload(["title": title, "current": current])
        return """
        (() => { \(prelude(encoded)) \
        let target = queue.slice(playing + 1).find((row) => titleOf(row) === want.title.trim()); \
        if (!target) { target = Array.from(document.querySelectorAll('ytmusic-responsive-list-item-renderer')) \
        .find((row) => titleOf(row) === want.title.trim()); } \
        if (!target) return 'missing'; \
        const button = target.querySelector('ytmusic-menu-renderer yt-button-shape button, ytmusic-menu-renderer button'); \
        if (!button) return 'nomenu'; \
        button.click(); return 'opened'; })()
        """
    }

    /// Picks Play next in the open menu by its label (the page's item data is not visible to Apple
    /// Events scripts). Closes the menu when the item isn't there.
    static func choosePlayNextScript(current: String) throws -> String {
        let encoded = try payload(["current": current])
        return """
        (() => { \(prelude(encoded)) \
        const words = ['play next', 'redă după melodia actuală', 'redă următoarea']; \
        const menu = Array.from(document.querySelectorAll('tp-yt-iron-dropdown')) \
        .find((box) => box.querySelector('ytmusic-menu-popup-renderer') && getComputedStyle(box).display !== 'none'); \
        if (!menu) return 'nomenu'; \
        const hit = Array.from(menu.querySelectorAll('ytmusic-menu-service-item-renderer')) \
        .find((item) => words.includes((item.textContent || '').trim().toLowerCase())); \
        if (!hit) { if (menu.close) menu.close(); return 'noitem'; } \
        hit.click(); return 'ok'; })()
        """
    }
}
