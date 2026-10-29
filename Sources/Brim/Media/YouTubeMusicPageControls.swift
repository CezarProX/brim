import Foundation

/// Next and Previous pressed on the YouTube Music page itself, through Chrome's page scripting.
/// Used when macOS won't route the media command to the app: the accessibility fallback reads the
/// app's tree, which can name the previous song for a whole track, so it refused to skip (seen live).
/// The page's Media Session always names the playing song, so that is what this checks.
extension YouTubeMusicQueueReader {
    static func pressTransport(_ command: NowPlayingCommand, expected: NowPlayingSnapshot) async throws {
        let output = try await runInTabs(
            for: expected.source, javaScript: try transportScript(command, current: expected.title))
        guard output.split(whereSeparator: \.isNewline).contains("ok") else {
            throw NowPlayingFailure.unavailable("The song changed. Try the control again.")
        }
    }

    /// Clicks the player's Next (or Previous) button in the tab playing `current`. The button is
    /// found by its label, else by its place beside Play/Pause (the only tonal button in the controls).
    /// Single quotes only, so it embeds in AppleScript unchanged.
    static func transportScript(_ command: NowPlayingCommand, current: String) throws -> String {
        let forward: Bool
        switch command {
        case .next: forward = true
        case .previous: forward = false
        default: throw NowPlayingFailure.unavailable("This YouTube Music control is unavailable.")
        }
        let encoded = try JSONEncoder().encode(["current": current]).base64EncodedString()
        let labels = forward ? "['next', 'înainte']" : "['previous', 'înapoi']"
        let step = forward ? 1 : -1
        return """
        (() => { \(pageGuard) \
        const want = JSON.parse(new TextDecoder().decode(Uint8Array.from(atob('\(encoded)'), (c) => c.charCodeAt(0)))); \
        const same = (a, b) => { a = a.trim().toLowerCase(); b = b.trim().toLowerCase(); \
        return a !== '' && b !== '' && (a === b || [' (', ' ['].some((s) => a.startsWith(b + s) || b.startsWith(a + s))); }; \
        const meta = navigator.mediaSession && navigator.mediaSession.metadata; \
        if (!meta || !same(meta.title || '', want.current)) return 'other'; \
        const buttons = Array.from(document.querySelectorAll('ytmusic-wiz-player-controls button, ytmusic-player-bar button')) \
        .filter((b) => b.getBoundingClientRect().width > 0); \
        let hit = buttons.find((b) => \(labels).includes((b.getAttribute('aria-label') || '').trim().toLowerCase())); \
        if (!hit) { const play = buttons.findIndex((b) => b.className.toString().includes('Tonal')); \
        hit = play >= 0 ? buttons[play + (\(step))] : null; } \
        if (!hit) return 'missing'; \
        hit.click(); return 'ok'; })()
        """
    }
}
