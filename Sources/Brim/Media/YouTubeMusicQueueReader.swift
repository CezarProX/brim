import AppKit
import ApplicationServices
import os

/// Reads and drives YouTube Music's upcoming songs.
///
/// The installed web app is read through Accessibility, like its player bar: no page scripting is
/// needed. Chromium only exposes the player page's "Up next" list while that page is open; with it
/// closed, the page of the playlist that is playing stands in (see `YouTubeQueueParsing`).
/// Browser tabs are only a source when "Allow JavaScript from Apple Events" is on (that is how their
/// song is read), so their queue is read by the same kind of page script, which also works with the
/// player page closed. Chrome's own process never gets the full accessibility tree turned on.
enum YouTubeMusicQueueReader {
    private static let log = Logger(subsystem: "io.github.cezarprox.brim", category: "playing-next")
    private static let queue = DispatchQueue(label: "brim.youtube-queue", qos: .userInitiated)
    private static let enabledPIDs = OSAllocatedUnfairLock(initialState: Set<pid_t>())
    private static let nodeBudget = 8000

    // MARK: Entry points

    static func upcoming(after snapshot: NowPlayingSnapshot, limit: Int) async throws -> [QueueItem] {
        switch snapshot.source {
        case .youtubeApp:
            // The app is a Chrome app window: page scripting reads its real queue. Without it (Chrome's
            // "Allow JavaScript from Apple Events" off) the list comes from the accessibility tree.
            if let output = try? await MusicQueueReader.run(browserScript(for: snapshot.source, javaScript: browserReadScript)) {
                let rows = YouTubeQueueParsing.browserUpcoming(output, title: snapshot.title, artist: snapshot.artist, limit: limit)
                if !rows.isEmpty { return YouTubeQueueParsing.items(rows) }
            }
            let rows = try await onQueue {
                let page = try capture()
                return YouTubeQueueParsing.upcoming(in: page.nodes, title: snapshot.title, artist: snapshot.artist,
                                                    limit: limit)
            }
            return YouTubeQueueParsing.items(rows)
        case .youtubeChrome, .youtubeSafari:
            let output = try await MusicQueueReader.run(browserScript(for: snapshot.source, javaScript: browserReadScript))
            return YouTubeQueueParsing.items(YouTubeQueueParsing.browserUpcoming(
                output, title: snapshot.title, artist: snapshot.artist, limit: limit))
        case .music, .spotify:
            return []
        }
    }

    /// Starts a queued song, after checking the page still shows it after the playing one.
    static func play(_ item: QueueItem, current snapshot: NowPlayingSnapshot) async throws {
        switch snapshot.source {
        case .youtubeApp, .youtubeChrome, .youtubeSafari:
            // Not an accessibility press: the app's row buttons only show on hover, and pressing them
            // through accessibility reports success while doing nothing (checked on the live app).
            let output = try await MusicQueueReader.run(browserScript(for: snapshot.source, javaScript: try browserPlayScript(
                item: item, current: snapshot)))
            guard output.split(whereSeparator: \.isNewline).contains("ok") else { throw NowPlayingFailure.unavailable("The queued song is no longer listed.") }
        case .music, .spotify:
            throw NowPlayingFailure.unavailable("This player has no YouTube Music queue.")
        }
    }

    /// The row's cover: its thumbnail (square-cropped) or the album picture the page showed.
    static func artwork(for item: QueueItem) async -> Data? {
        guard let url = item.artworkURL, NowPlayingSnapshot.safeArtworkURL(url) != nil else { return nil }
        let probe = NowPlayingSnapshot(source: .youtubeApp, title: item.title, artist: item.artist, album: "",
                                       duration: item.duration, position: 0, isPlaying: false, artworkURL: url)
        return await NowPlayingArtwork.load(probe)
    }

    private static func onQueue<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { continuation.resume(with: Result { try work() }) }
        }
    }

    // MARK: Accessibility (the installed web app)

    private struct Page {
        let nodes: [YouTubeQueueNode]
        let elements: [AXUIElement]
    }

    /// The YouTube Music document's nodes in document order, with their elements.
    private static func capture() throws -> Page {
        guard NowPlayingAccessibility.isTrusted else { throw NowPlayingFailure.accessibility }
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: NowPlayingSource.youtubeApp.bundleID)
            .first(where: { !$0.isTerminated }) else { throw NowPlayingFailure.notRunning(NowPlayingSource.youtubeApp.name) }
        let pid = app.processIdentifier
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.15)
        requestFullTree(application, pid: pid)
        guard let document = webArea(in: application) else { return Page(nodes: [], elements: []) }
        return walk(document)
    }

    /// The app shim only, exactly as the player reader does: never Chrome's own process, where the
    /// full tree made typing slow (see `NowPlayingAccessibility.releaseChromeFullTree`).
    private static func requestFullTree(_ application: AXUIElement, pid: pid_t) {
        guard enabledPIDs.withLock({ $0.insert(pid).inserted }) else { return }
        AXUIElementSetAttributeValue(application, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }

    private static func webArea(in application: AXUIElement) -> AXUIElement? {
        var pending: [(AXUIElement, Int)] = [(application, 0)]
        var visited = 0
        while !pending.isEmpty, visited < 400 {
            let (element, depth) = pending.removeFirst()
            visited += 1
            let role = attribute(element, kAXRoleAttribute) as? String
            if role == "AXWebArea", let raw = attribute(element, kAXURLAttribute),
               let url = NowPlayingAccessibility.urlString(raw), URL(string: url)?.host == "music.youtube.com" {
                return element
            }
            guard depth < 10 else { continue }
            for child in attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] { pending.append((child, depth + 1)) }
        }
        return nil
    }

    private static func walk(_ root: AXUIElement) -> Page {
        let keys = [kAXRoleAttribute, kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute, kAXURLAttribute,
                    kAXChildrenAttribute]
        let deadline = Date().addingTimeInterval(2.5)
        var nodes: [YouTubeQueueNode] = []
        var elements: [AXUIElement] = []
        var pending: [(AXUIElement, Int)] = [(root, 0)]
        while let (element, depth) = pending.popLast(), nodes.count < nodeBudget, Date() < deadline {
            var raw: CFArray?
            guard AXUIElementCopyMultipleAttributeValues(element, keys as CFArray, [], &raw) == .success,
                  let values = raw as? [Any], values.count == keys.count else { continue }
            let label = [values[1], values[2], values[3]].compactMap { $0 as? String }.first { !$0.isEmpty } ?? ""
            nodes.append(YouTubeQueueNode(role: values[0] as? String ?? "", label: String(label.prefix(1024)),
                                          url: NowPlayingAccessibility.urlString(values[4]) ?? "",
                                          isOn: (values[3] as? NSNumber)?.boolValue))
            elements.append(element)
            guard depth < 60 else { continue }
            // Reversed so the stack pops children in document order.
            for child in (values[5] as? [AXUIElement] ?? []).prefix(4000).reversed() { pending.append((child, depth + 1)) }
        }
        if nodes.count >= nodeBudget { log.info("YouTube Music queue walk stopped at \(nodes.count) nodes") }
        return Page(nodes: nodes, elements: elements)
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    // MARK: Browser tabs (page scripting, opt-in)

    static let queueItems = "Array.from(document.querySelectorAll('ytmusic-player-queue ytmusic-player-queue-item'))"
        + ".filter((item) => !item.closest('#counterpart-renderer'))"
    static let pageGuard = "if (location.protocol !== 'https:' || location.hostname !== 'music.youtube.com') return 'null';"

    /// Runs in the page's own world (Apple Events scripts run in an isolated one, which can't see
    /// element data): each queue row's video id and largest cover, in queue order, left as JSON on
    /// the document for the isolated script to take. Fixed code; page data never enters it.
    static let mainWorldQueue = """
    (() => { const rows = \(queueItems).map((item) => { \
    let d = item.data || (item.__data && item.__data.data) || {}; \
    if (d.playlistPanelVideoRenderer) d = d.playlistPanelVideoRenderer; \
    if (d.primaryRenderer && d.primaryRenderer.playlistPanelVideoRenderer) d = d.primaryRenderer.playlistPanelVideoRenderer; \
    const shots = (d.thumbnail && d.thumbnail.thumbnails) || []; \
    return { v: d.videoId || '', i: shots.length ? shots[shots.length - 1].url : '' }; }); \
    document.documentElement.setAttribute('data-brim-queue', JSON.stringify(rows)); })()
    """

    /// Isolated-world prelude that runs `mainWorldQueue` as a page script (the page requires Trusted
    /// Types and its script nonce) and reads its result into `deep`; empty when that is refused.
    static let deepQueue = """
    const deep = (() => { try { const marker = document.querySelector('script[nonce]'); \
    const policy = window.trustedTypes ? (window.brimQueuePolicy || (window.brimQueuePolicy = \
    trustedTypes.createPolicy('brim-queue-' + Date.now(), { createScript: (code) => code }))) : null; \
    const script = document.createElement('script'); if (marker) script.nonce = marker.nonce || marker.getAttribute('nonce'); \
    const code = atob('\(Data(mainWorldQueue.utf8).base64EncodedString())'); \
    script.textContent = policy ? policy.createScript(code) : code; \
    document.documentElement.appendChild(script); script.remove(); \
    const out = JSON.parse(document.documentElement.getAttribute('data-brim-queue') || '[]'); \
    document.documentElement.removeAttribute('data-brim-queue'); return Array.isArray(out) ? out : []; \
    } catch (error) { return []; } })();
    """

    /// One JSON line per tab: title, byline, duration text, thumbnail and whether it is the playing item.
    /// Written without double quotes or backslashes so it embeds in AppleScript unchanged.
    /// Queue covers only load while the queue is on screen, so a closed queue shows blank images; the
    /// page's own row data (`deep`) has every row's cover and video id (checked live: none of the
    /// rows after the playing one had a loaded picture). Failing that, the same songs elsewhere on the
    /// page give their real cover: `p` a picture, `v` a video id, both matched by exact title.
    static let browserReadScript = """
    (() => { \(pageGuard) \
    \(deepQueue) \
    const text = (root, selector) => { const node = root.querySelector(selector); \
    return ((node && (node.getAttribute('title') || node.textContent)) || '').trim(); }; \
    const seen = {}; \
    Array.from(document.querySelectorAll('a[href*=watch]')).forEach((link) => { \
    const name = (link.getAttribute('title') || link.textContent || '').trim(); \
    const v = new URL(link.href, location.href).searchParams.get('v'); \
    if (name && v && !seen[name]) seen[name] = { v: v }; }); \
    Array.from(document.querySelectorAll('ytmusic-responsive-list-item-renderer')).forEach((row) => { \
    const name = text(row, 'yt-formatted-string.title'); const image = row.querySelector('img'); \
    if (name && image && image.src.startsWith('https:')) seen[name] = Object.assign(seen[name] || {}, { p: image.src }); }); \
    return JSON.stringify(\(queueItems).slice(0, 200).map((item, index) => { const image = item.querySelector('img'); \
    const title = text(item, '.song-title'); const known = seen[title] || {}; const own = deep[index] || {}; \
    const loaded = image && image.src.startsWith('https:') ? image.src : ''; \
    return { t: title, a: text(item, '.byline'), d: text(item, '.duration'), \
    i: loaded || own.i || '', s: item.hasAttribute('selected'), v: own.v || known.v || '', p: known.p || '' }; })); })()
    """

    /// Clicks one queue item after checking it still holds the expected song and that the tab's
    /// selected item is the playing song. Page data reaches the script only as base64 JSON.
    static func browserPlayScript(item: QueueItem, current snapshot: NowPlayingSnapshot) throws -> String {
        let position = item.index - 1
        guard position >= 0 else { throw NowPlayingFailure.unavailable("The queued song is no longer listed.") }
        struct Want: Encodable { let title: String; let current: String }
        let payload = try JSONEncoder().encode(Want(title: item.title, current: snapshot.title)).base64EncodedString()
        return """
        (() => { \(pageGuard) \
        const want = JSON.parse(new TextDecoder().decode(Uint8Array.from(atob('\(payload)'), (c) => c.charCodeAt(0)))); \
        const items = \(queueItems); \
        const titleOf = (item) => { const node = item && item.querySelector('.song-title'); \
        return ((node && (node.getAttribute('title') || node.textContent)) || '').trim(); }; \
        const same = (a, b) => { a = a.trim().toLowerCase(); b = b.trim().toLowerCase(); \
        return a !== '' && b !== '' && (a === b || [' (', ' ['].some((s) => a.startsWith(b + s) || b.startsWith(a + s))); }; \
        const playing = items.find((item) => item.hasAttribute('selected')); \
        if (!playing || !same(titleOf(playing), want.current)) return 'unavailable'; \
        const target = items[\(position)]; \
        if (!target || titleOf(target) !== want.title.trim()) return 'unavailable'; \
        (target.querySelector('ytmusic-play-button-renderer') || target.querySelector('.song-title')).click(); \
        return 'ok'; })()
        """
    }

    /// Runs `javaScript` in every music.youtube.com tab, one result per line.
    static func browserScript(for source: NowPlayingSource, javaScript: String) -> String {
        // The YouTube Music app is a Chrome app window, so Chrome's scripting reaches its page too.
        let chrome = source != .youtubeSafari
        let bundle = chrome ? NowPlayingSource.youtubeChrome.bundleID : source.bundleID
        let run = chrome ? "execute qTab javascript \"\(javaScript)\"" : "do JavaScript \"\(javaScript)\" in qTab"
        return """
        tell application id "\(bundle)"
          set qOut to ""
          repeat with qWindow in windows
            repeat with qTab in tabs of qWindow
              if (URL of qTab as text) starts with "https://music.youtube.com/" then
                set qResult to \(run)
                if qResult is not missing value then set qOut to qOut & (qResult as text) & linefeed
              end if
            end repeat
          end repeat
          return qOut
        end tell
        """
    }
}
