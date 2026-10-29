import Foundation

/// MediaRemote names a song the way the app reports it; YouTube Music's page reads it differently
/// ("A și B" there, "A · B" on the page; extra "[From …]" suffixes). Treating those as different songs
/// made every poll replace the stream's song and throw its cover away.
enum NowPlayingSongMatch {
    /// How far apart the two lengths may be (the page rounds to whole seconds).
    static let durationTolerance: TimeInterval = 2

    /// The poll folded into the stream's song when both describe the same one: the stream's names and
    /// cover bytes, the poll's playback state and what only the page knows (its link and cover URL).
    /// nil when the poll is a different song (or can't be told apart), so it is taken as is.
    static func merge(poll: NowPlayingSnapshot, into stream: NowPlayingSnapshot) -> NowPlayingSnapshot? {
        guard poll.source == stream.source, poll.duration > 0, stream.duration > 0,
              abs(poll.duration - stream.duration) <= durationTolerance,
              sameTitle(poll.title, stream.title) || sharesArtist(poll.artist, stream.artist) else { return nil }
        var merged = NowPlayingSnapshot(
            source: stream.source, title: stream.title, artist: stream.artist,
            album: stream.album.isEmpty ? poll.album : stream.album,
            duration: stream.duration, position: poll.position, isPlaying: poll.isPlaying,
            artworkData: poll.artworkData ?? stream.artworkData, artworkURL: poll.artworkURL ?? stream.artworkURL,
            albumURL: poll.albumURL ?? stream.albumURL,
            isFavorite: poll.isFavorite ?? stream.isFavorite, isShuffling: poll.isShuffling ?? stream.isShuffling)
        merged.pageURL = poll.pageURL ?? stream.pageURL
        merged.playbackRate = poll.playbackRate
        merged.repeatMode = poll.repeatMode ?? stream.repeatMode
        return merged
    }

    /// Equal once case, accents and any "(…)", "[…]" or " - …" tail are set aside.
    static func sameTitle(_ a: String, _ b: String) -> Bool {
        let left = core(a), right = core(b)
        return !left.isEmpty && left == right
    }

    /// Any artist name in common, however the list is joined.
    static func sharesArtist(_ a: String, _ b: String) -> Bool {
        let left = Set(names(a)), right = Set(names(b))
        return !left.isDisjoint(with: right)
    }

    private static func core(_ title: String) -> String {
        var text = fold(title)
        for marker in [" (", " [", " - "] {
            if let range = text.range(of: marker) { text = String(text[..<range.lowerBound]) }
        }
        return text.trimmingCharacters(in: .whitespaces)
    }

    private static func names(_ artists: String) -> [String] {
        var text = " " + fold(artists) + " "
        for separator in [" · ", " • ", ", ", " & ", " și ", " si ", " and ", " feat. ", " ft. ", " x "] {
            text = text.replacingOccurrences(of: separator, with: "\u{1F}")
        }
        return text.split(separator: "\u{1F}").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
