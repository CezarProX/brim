import Foundation

/// One accessibility node of the YouTube Music page, in document order, as the queue parser reads it.
struct YouTubeQueueNode: Equatable, Sendable {
    var role: String
    var label: String
    var url: String = ""
    /// A toggle's AXValue (shuffle); nil for nodes without a numeric value.
    var isOn: Bool?
}

/// A song row found on the page.
struct YouTubeQueueRow: Equatable, Sendable {
    let title: String
    let artist: String
    let duration: TimeInterval
    let videoID: String?
    let artworkURL: String?
    /// 1-based order among the rows of its list.
    let position: Int
    /// What a click presses: an index into the node list (Accessibility), or the queue item's
    /// index on the page (browser scripting).
    let pressIndex: Int
    /// The row shows a Pause button or is the queue's selected item: the song playing now.
    let isPlaying: Bool
}

/// Finds YouTube Music's upcoming songs in what the page exposes, without scripting it.
///
/// Chromium flattens YouTube Music's list items: a playlist row is a run of siblings (play button,
/// title link, artist links, "•", album link, menu, a duration group, the "4:38" text, a checkbox),
/// so rows are cut at their duration text rather than found as containers.
enum YouTubeQueueParsing {
    static let playWords = ["Play", "Redă", "Redare"]
    static let pauseWords = ["Pause", "Pauză", "Întrerupe", "Întrerupe redarea"]
    /// The player page's queue tab, compared case- and accent-insensitively.
    static let upNextTabs = ["up next", "urmeaza", "in continuare"]
    static let shuffleLabels = ["shuffle", "reda aleatoriu", "redare aleatorie", "amesteca"]
    /// Where the page's own lists end: the player bar (its slider, "Now playing", the controls).
    static let playerBarLabels = ["Now playing", "PLAYBACK_CONTROLS", "Player bar", "Bara playerului"]

    private static let textRole = "AXStaticText"
    private static let softRoles: Set<String> = ["AXGroup", "AXGenericElement", "AXUnknown", ""]

    // MARK: Upcoming songs

    /// The songs after the playing one. The player page's "Up next" list wins; without it (the player
    /// page is closed and Chromium drops it from the tree), the page of the playlist that is playing,
    /// in its own order, unless shuffle is on. Empty when the playing song can't be placed in either.
    static func upcoming(in nodes: [YouTubeQueueNode], title: String, artist: String, limit: Int) -> [YouTubeQueueRow] {
        for range in [queueRange(nodes), playlistRange(nodes)].compactMap({ $0 }) {
            let found = rows(in: nodes, range: range)
            if let next = after(current: title, artist: artist, in: found) { return Array(next.prefix(limit)) }
        }
        return []
    }

    /// The rows after the playing one, or nil when no row is the playing song.
    static func after(current title: String, artist: String, in rows: [YouTubeQueueRow]) -> ArraySlice<YouTubeQueueRow>? {
        guard let index = rows.firstIndex(where: \.isPlaying)
                ?? rows.firstIndex(where: { sameSong($0, title: title, artist: artist) }) else { return nil }
        return rows[(index + 1)...]
    }

    static func items(_ rows: [YouTubeQueueRow]) -> [QueueItem] {
        rows.map { row in
            QueueItem(index: row.position, persistentID: identity(row), title: String(row.title.prefix(512)),
                      artist: String(row.artist.prefix(512)), duration: row.duration,
                      artworkURL: row.artworkURL ?? row.videoID.flatMap(thumbnailURL(videoID:)))
        }
    }

    /// The video id when the page exposes one, otherwise the song's title and artist.
    static func identity(_ row: YouTubeQueueRow) -> String {
        row.videoID ?? "t:\(fold(row.title))|\(fold(row.artist))"
    }

    /// The small 16:9 thumbnail every video has (its square center is the cover).
    static func thumbnailURL(videoID: String) -> String? {
        guard videoID.range(of: #"^[A-Za-z0-9_-]{11}$"#, options: .regularExpression) != nil else { return nil }
        return "https://i.ytimg.com/vi/\(videoID)/mqdefault.jpg"
    }

    /// Titles match exactly or up to a featured-artist suffix ("Fancy" / "Fancy (cu T.I. și Swizz Beatz)");
    /// artists must overlap when both are known.
    static func sameSong(_ row: YouTubeQueueRow, title: String, artist: String) -> Bool {
        let rowTitle = fold(row.title), wanted = fold(title)
        guard !rowTitle.isEmpty, !wanted.isEmpty else { return false }
        let titleMatches = rowTitle == wanted || [" (", " ["].contains { suffix in
            rowTitle.hasPrefix(wanted + suffix) || wanted.hasPrefix(rowTitle + suffix)
        }
        guard titleMatches else { return false }
        let rowArtist = fold(row.artist), wantedArtist = fold(artist)
        guard !rowArtist.isEmpty, !wantedArtist.isEmpty else { return true }
        let lead = rowArtist.components(separatedBy: " · ").first ?? rowArtist
        return wantedArtist.contains(lead) || rowArtist.contains(wantedArtist)
    }

    // MARK: Lists on the page

    /// After the player page's "Up next" tab, up to the player bar.
    static func queueRange(_ nodes: [YouTubeQueueNode]) -> Range<Int>? {
        guard let tab = nodes.firstIndex(where: { $0.role != textRole && upNextTabs.contains(fold($0.label)) })
        else { return nil }
        return (tab + 1)..<playerBarStart(nodes, from: tab + 1)
    }

    /// The rows of a playlist (or album) page whose header button reads "Pause <its title>": that list
    /// is the one playing. Skipped while shuffle is on, since the queue then no longer follows the page.
    static func playlistRange(_ nodes: [YouTubeQueueNode]) -> Range<Int>? {
        guard !nodes.contains(where: { shuffleLabels.contains(fold($0.label)) && $0.isOn == true }) else { return nil }
        for (index, heading) in nodes.enumerated() where heading.role == "AXHeading" && !heading.label.isEmpty {
            let window = (index + 1)..<min(nodes.count, index + 40)
            let header = window.first { candidate in
                nodes[candidate].role == "AXButton"
                    && pauseWords.contains { nodes[candidate].label == "\($0) \(heading.label)" }
            }
            if let header { return (header + 1)..<playerBarStart(nodes, from: header + 1) }
        }
        return nil
    }

    private static func playerBarStart(_ nodes: [YouTubeQueueNode], from start: Int) -> Int {
        guard start < nodes.count else { return nodes.count }
        return nodes[start...].firstIndex { $0.role == "AXSlider" || playerBarLabels.contains($0.label) } ?? nodes.count
    }

    // MARK: Rows

    /// One row per duration text ("4:38"), built from the nodes since the previous one.
    static func rows(in nodes: [YouTubeQueueNode], range: Range<Int>) -> [YouTubeQueueRow] {
        var rows: [YouTubeQueueRow] = []
        var start = range.lowerBound
        for index in range where nodes[index].role == textRole {
            guard let duration = durationSeconds(nodes[index].label) else { continue }
            if let row = row(nodes, window: start..<index, duration: duration, position: rows.count + 1) {
                rows.append(row)
            }
            start = index + 1
        }
        return rows
    }

    private static func row(_ nodes: [YouTubeQueueNode], window: Range<Int>, duration: TimeInterval,
                            position: Int) -> YouTubeQueueRow? {
        guard !window.isEmpty else { return nil }
        let image = window.last { nodes[$0].role == "AXImage" && NowPlayingSnapshot.safeArtworkURL(nodes[$0].url) != nil }
        let imageURL = image.map { nodes[$0].url }
        let titleIndex: Int, title: String, artist: String, videoID: String?
        // Playlist row: the title links to the song; artists are channel links until the "•". A link
        // whose URL Chromium didn't report still counts, the title being the row's first link.
        let link = window.first { nodes[$0].role == "AXLink" && YouTubeThumbnail.videoID(from: nodes[$0].url) != nil }
            ?? window.first { nodes[$0].role == "AXLink" && nodes[$0].url.isEmpty && !nodes[$0].label.isEmpty }
        if let link {
            titleIndex = link
            title = clean(nodes[link].label)
            videoID = YouTubeThumbnail.videoID(from: nodes[link].url)
            var names: [String] = []
            for next in (link + 1)..<window.upperBound {
                let node = nodes[next]
                if node.role == textRole, node.label.contains("•") { break }
                guard node.role == "AXLink" else { continue }
                guard isChannel(node.url) || node.url.isEmpty else { break }
                let name = clean(node.label)
                if !name.isEmpty, !names.contains(name) { names.append(name) }
            }
            artist = names.joined(separator: " · ")
        } else {
            // Queue item: plain texts right before the duration, the title first, then the byline.
            var texts: [Int] = []
            var cursor = window.upperBound - 1
            while cursor >= window.lowerBound {
                let role = nodes[cursor].role
                if role == textRole { texts.insert(cursor, at: 0) } else if !softRoles.contains(role) { break }
                cursor -= 1
            }
            let labelled = texts.filter { !isSeparator(nodes[$0].label) }
            guard let first = labelled.first else { return nil }
            titleIndex = first
            title = clean(nodes[first].label)
            let byline = texts.drop { $0 <= first }.map { nodes[$0].label }.joined()
            artist = clean(byline.components(separatedBy: "•").first ?? "")
            videoID = imageURL.flatMap(videoID(fromThumbnail:))
        }
        guard !title.isEmpty else { return nil }
        let button = (window.lowerBound..<titleIndex).last { isPlayButton(nodes[$0]) }
        let playing = button.map { pauseWords.contains(where: nodes[$0].label.hasPrefix) } ?? false
        return YouTubeQueueRow(title: title, artist: artist, duration: duration, videoID: videoID,
                               artworkURL: imageURL, position: position, pressIndex: button ?? titleIndex,
                               isPlaying: playing)
    }

    /// A row's own button: "Redă Earned It - The Weeknd - …" or "Întrerupe …", never the action menu.
    static func isPlayButton(_ node: YouTubeQueueNode) -> Bool {
        guard node.role == "AXButton" else { return false }
        return (playWords + pauseWords).contains { word in
            node.label.hasPrefix(word + " ") && node.label.count > word.count + 1
        }
    }

    static func durationSeconds(_ value: String) -> TimeInterval? {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.range(of: #"^\d{1,2}:\d{2}(:\d{2})?$"#, options: .regularExpression) != nil else { return nil }
        return text.split(separator: ":").reduce(0) { $0 * 60 + (Double($1) ?? 0) }
    }

    static func videoID(fromThumbnail value: String) -> String? {
        guard let url = URL(string: value), url.host == "i.ytimg.com" else { return nil }
        let parts = url.path.split(separator: "/")
        guard parts.count >= 2, parts[0] == "vi" || parts[0] == "vi_webp" else { return nil }
        let id = String(parts[1])
        return id.range(of: #"^[A-Za-z0-9_-]{11}$"#, options: .regularExpression) != nil ? id : nil
    }

    private static func isChannel(_ value: String) -> Bool {
        guard let url = URL(string: value), url.host == "music.youtube.com" else { return false }
        return url.path.hasPrefix("/channel/") || url.path.hasPrefix("/browse/UC")
    }

    private static func isSeparator(_ value: String) -> Bool {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty || text == "•"
    }

    private static func clean(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func fold(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Browser scripting

    /// One `ytmusic-player-queue-item` as `YouTubeMusicQueueReader.browserReadScript` reports it.
    private struct BrowserRow: Decodable {
        let t: String
        let a: String
        let d: String
        let i: String
        let s: Bool
        /// The same song's video id and loaded picture found elsewhere on the page.
        var v: String?
        var p: String?
    }

    /// Rows from one tab's JSON line. Malformed or oversized output reads as no rows.
    static func browserRows(_ json: String) -> [YouTubeQueueRow] {
        guard json.utf8.count < 262_144,
              let decoded = try? JSONDecoder().decode([BrowserRow].self, from: Data(json.utf8)) else { return [] }
        var rows: [YouTubeQueueRow] = []
        for (index, item) in decoded.enumerated() {
            let title = clean(item.t)
            guard !title.isEmpty else { continue }
            // The row's own picture, else the same song's elsewhere on the page; a blank lazy image is neither.
            let artwork = [item.i, item.p ?? ""].first { NowPlayingSnapshot.safeArtworkURL($0) != nil }
            let pageVideo = (item.v ?? "").range(of: #"^[A-Za-z0-9_-]{11}$"#, options: .regularExpression) != nil ? item.v : nil
            rows.append(YouTubeQueueRow(
                title: title, artist: clean(item.a.components(separatedBy: "•").first ?? ""),
                duration: durationSeconds(item.d) ?? 0, videoID: artwork.flatMap(videoID(fromThumbnail:)) ?? pageVideo,
                artworkURL: artwork, position: index + 1, pressIndex: index, isPlaying: item.s))
        }
        return rows
    }

    /// The upcoming songs from the first tab (one JSON line each) where the playing song is found.
    static func browserUpcoming(_ output: String, title: String, artist: String, limit: Int) -> [YouTubeQueueRow] {
        for line in output.split(whereSeparator: \.isNewline) {
            if let next = after(current: title, artist: artist, in: browserRows(String(line))) {
                return Array(next.prefix(limit))
            }
        }
        return []
    }
}
