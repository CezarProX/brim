import Foundation

/// Browser scripting is opt-in. Only the YouTube Music origin is inspected; no page text leaves the Mac.
enum NowPlayingBrowser {
    private static func all(_ kind: String, in container: NSAppleEventDescriptor = .null()) -> NSAppleEventDescriptor {
        let ordinal = NSAppleEventDescriptor(enumCode: NowPlayingAppleEvents.code("all "))
            .coerce(toDescriptorType: NowPlayingAppleEvents.code("abso")) ?? .null()
        return NowPlayingAppleEvents.object(want: kind, selector: ordinal, container: container)
    }

    private static func tabs(_ bridge: NowPlayingAppleEvents) throws -> [NSAppleEventDescriptor] {
        let windows = try bridge.get(all("cwin"))
        guard windows.numberOfItems > 0 else { return [] }
        var result: [NSAppleEventDescriptor] = []
        for index in 1...min(windows.numberOfItems, 8) {
            guard let window = windows.atIndex(index) else { continue }
            let tabs = try bridge.get(all(bridge.source == .youtubeChrome ? "CrTb" : "bTab", in: window))
            guard tabs.numberOfItems > 0 else { continue }
            let URLs = try bridge.get(NowPlayingAppleEvents.property(bridge.source == .youtubeChrome ? "URL " : "pURL",
                of: all(bridge.source == .youtubeChrome ? "CrTb" : "bTab", in: window)))
            for tabIndex in 1...min(tabs.numberOfItems, 200) {
                guard let tab = tabs.atIndex(tabIndex) else { continue }
                let value = URLs.atIndex(tabIndex)?.stringValue ?? ""
                guard let url = URL(string: value), url.scheme == "https", url.host == "music.youtube.com" else { continue }
                result.append(tab)
            }
        }
        return result
    }

    static func snapshot(_ bridge: NowPlayingAppleEvents) throws -> NowPlayingSnapshot? {
        try current(bridge)?.snapshot
    }

    private static func current(_ bridge: NowPlayingAppleEvents) throws -> (tab: NSAppleEventDescriptor, snapshot: NowPlayingSnapshot)? {
        var paused: (NSAppleEventDescriptor, NowPlayingSnapshot)?
        for tab in try tabs(bridge) {
            let json = try execute(script(for: nil), tab: tab, bridge: bridge)
            if let snapshot = try NowPlayingSnapshot.browserJSON(json, source: bridge.source) {
                if snapshot.isPlaying { return (tab, snapshot) }
                if paused == nil { paused = (tab, snapshot) }
            }
        }
        return paused
    }

    /// Selects the existing playing tab instead of opening a duplicate song in another tab.
    static func focusPlayingTab(expected: NowPlayingSnapshot) throws -> Bool {
        let bridge = try NowPlayingAppleEvents(source: expected.source)
        let windows = try bridge.get(all("cwin"))
        guard windows.numberOfItems > 0 else { return false }
        for windowIndex in 1...min(windows.numberOfItems, 8) {
            guard let window = windows.atIndex(windowIndex) else { continue }
            let candidates = try bridge.get(all(expected.source == .youtubeChrome ? "CrTb" : "bTab", in: window))
            guard candidates.numberOfItems > 0 else { continue }
            for index in 1...min(candidates.numberOfItems, 200) {
                guard let tab = candidates.atIndex(index) else { continue }
                let property = NowPlayingAppleEvents.property(expected.source == .youtubeChrome ? "URL " : "pURL", of: tab)
                guard let raw = try bridge.get(property).stringValue, URL(string: raw)?.host == "music.youtube.com",
                      let snapshot = try NowPlayingSnapshot.browserJSON(execute(script(for: nil), tab: tab, bridge: bridge), source: expected.source),
                      snapshot.title == expected.title, snapshot.artist == expected.artist else { continue }
                _ = try bridge.send(eventClass: "core", eventID: "setd", parameters: [
                    "----": NowPlayingAppleEvents.property(expected.source == .youtubeChrome ? "acTI" : "cTab", of: window),
                    "data": expected.source == .youtubeChrome ? NSAppleEventDescriptor(int32: Int32(index)) : tab
                ])
                _ = try bridge.send(eventClass: "core", eventID: "setd", parameters: [
                    "----": NowPlayingAppleEvents.property("pidx", of: window), "data": NSAppleEventDescriptor(int32: 1)
                ])
                return true
            }
        }
        return false
    }

    static func perform(_ command: NowPlayingCommand, expected: NowPlayingSnapshot, bridge: NowPlayingAppleEvents) throws {
        guard let active = try current(bridge) else { throw NowPlayingFailure.unavailable("Start a song in YouTube Music first.") }
        guard active.snapshot.title == expected.title, active.snapshot.artist == expected.artist else {
            throw NowPlayingFailure.unavailable("The song changed. Try the control again.")
        }
        if case .seek(let position) = command {
            try NowPlayingSystemControls.validateSeek(position, duration: expected.duration)
            try NowPlayingSystemControls.validateSeek(position, duration: active.snapshot.duration)
        }
        let result = try execute(script(for: command), tab: active.tab, bridge: bridge)
        guard result == "ok" else { throw NowPlayingFailure.unavailable("This player control is unavailable. Open YouTube Music to continue.") }
    }

    private static func execute(_ javaScript: String, tab: NSAppleEventDescriptor,
                                bridge: NowPlayingAppleEvents) throws -> String {
        let result: NSAppleEventDescriptor
        if bridge.source == .youtubeChrome {
            result = try bridge.send(eventClass: "CrSu", eventID: "ExJa", parameters: ["----": tab, "JvSc": NSAppleEventDescriptor(string: javaScript)])
        } else {
            result = try bridge.send(eventClass: "sfri", eventID: "dojs", parameters: ["----": NSAppleEventDescriptor(string: javaScript), "dcnm": tab])
        }
        guard let text = result.stringValue, !text.isEmpty else {
            throw NowPlayingFailure.unavailable("Enable Allow JavaScript from Apple Events in your browser's developer menu, then try again.")
        }
        return text
    }

    static func script(for command: NowPlayingCommand?) -> String {
        // Everything interpolated below comes from this closed command enum, never page metadata.
        let action: String
        switch command {
        case .playPause: action = "const b = bar.querySelector('#play-pause-button'); if (!b) return 'unavailable'; b.click(); return 'ok';"
        case .next: action = "const b = bar.querySelector('.next-button'); if (!b) return 'unavailable'; b.click(); return 'ok';"
        case .previous: action = "const b = bar.querySelector('.previous-button'); if (!b) return 'unavailable'; b.click(); return 'ok';"
        case .seek(let position):
            if position.isFinite, position >= 0 {
                action = """
                const media = document.querySelector('video');
                const position = \(position);
                if (!media || !Number.isFinite(media.duration) || media.duration <= 0 || position > media.duration) return 'unavailable';
                media.currentTime = position;
                return 'ok';
                """
            } else { action = "return 'unavailable';" }
        case .setFavorite, .setShuffle, .setRepeat: action = "return 'unavailable';"
        case nil: action = """
            const media = document.querySelector('video');
            const metadata = navigator.mediaSession && navigator.mediaSession.metadata;
            const title = metadata?.title || bar.querySelector('.title')?.textContent?.trim() || '';
            if (!media || !title || media.ended || !media.currentSrc) return 'null';
            const image = metadata?.artwork?.[0]?.src || bar.querySelector('img')?.src || null;
            const links = Array.from(bar.querySelectorAll('a[href]'));
            const artistURL = links.map(a => a.href).find(h => {
              try { const u = new URL(h); const p = u.pathname.split('/');
                return u.origin === 'https://music.youtube.com' && ['channel', 'browse'].includes(p[1])
                  && /^UC[A-Za-z0-9_-]{10,120}$/.test(p[2] || ''); } catch (_) { return false; }
            }) || null;
            const player = document.querySelector('ytmusic-player');
            let videoID = null;
            try { videoID = player?.getPlayerResponse?.()?.videoDetails?.videoId || null; } catch (_) {}
            const pageURL = links.map(a => a.href).find(h => h.startsWith('https://music.youtube.com/watch?'))
              || (videoID && /^[A-Za-z0-9_-]{11}$/.test(videoID) ? 'https://music.youtube.com/watch?v=' + videoID : location.href);
            return JSON.stringify({title, artist: metadata?.artist || bar.querySelector('.byline')?.textContent?.trim() || '',
              pageURL, artistURL, album: metadata?.album || '', position: Number.isFinite(media.currentTime) ? media.currentTime : 0,
              duration: Number.isFinite(media.duration) ? media.duration : 0, isPlaying: !media.paused, artworkURL: image});
            """
        }
        return """
        (() => {
          if (location.protocol !== 'https:' || location.hostname !== 'music.youtube.com') return 'null';
          const bar = document.querySelector('ytmusic-player-bar');
          if (!bar) return 'null';
          \(action)
        })()
        """
    }
}
