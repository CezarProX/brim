import AppKit
import Foundation
import ImageIO
import os
import SwiftUI

/// One upcoming song in the "Playing Next" list.
struct QueueItem: Identifiable, Equatable, Sendable {
    /// Position inside the playing playlist (1-based), which is how the player jumps to it.
    let index: Int
    let persistentID: String
    let title: String
    let artist: String
    let duration: TimeInterval
    /// A cover the page showed for the row (YouTube Music); Apple Music covers are read by index.
    var artworkURL: String?
    var id: String { "\(index)-\(persistentID)" }
}

/// What each source can really do with a queue. Apple Music exposes its playlist to scripting and
/// YouTube Music shows its upcoming songs on the page; Spotify gives no readable queue, so the
/// queue button is hidden for it.
enum QueueCapability {
    static func supportsQueue(_ source: NowPlayingSource?) -> Bool {
        switch source {
        case .music, .youtubeApp, .youtubeChrome, .youtubeSafari: return true
        case .spotify, nil: return false
        }
    }
}

/// One player's queue as `PlayingNextModel` drives it: read the songs after the playing one,
/// start one of them, load a row's cover.
struct QueueBackend {
    let read: (NowPlayingSnapshot, Int) async throws -> [QueueItem]
    let play: (QueueItem, NowPlayingSnapshot) async throws -> Void
    let artwork: (QueueItem) async -> Data?
    /// An empty read may only mean the list isn't on screen yet (YouTube Music's player page is
    /// closed), so the next refresh for the same song reads again instead of trusting it.
    var retriesWhenEmpty = false
    /// The player's own "Play next" (YouTube Music's menu item), which reorders its real queue so any
    /// skip honours it. nil: Brim keeps the pick and starts it when the song changes.
    var playNext: ((QueueItem, NowPlayingSnapshot) async throws -> Void)? = nil

    /// Apple Music through `MusicQueueReader`'s scripts, or any closures answering in that format.
    static func script(read: @escaping (Int) async throws -> String, perform: @escaping (String) async throws -> String,
                       fetchArtwork: @escaping (Int) async -> Data?) -> QueueBackend {
        QueueBackend(read: { _, limit in QueueParsing.parse(try await read(limit)) },
                     play: { item, _ in _ = try await perform(MusicQueueReader.playScript(index: item.index)) },
                     artwork: { await fetchArtwork($0.index) })
    }

    static var appleMusic: QueueBackend {
        script(read: { try await MusicQueueReader.run(MusicQueueReader.script(limit: $0)) },
               perform: { try await MusicQueueReader.run($0) },
               fetchArtwork: { await MusicQueueReader.artwork(index: $0) })
    }

    static var youTubeMusic: QueueBackend {
        QueueBackend(read: { try await YouTubeMusicQueueReader.upcoming(after: $0, limit: $1) },
                     play: { try await YouTubeMusicQueueReader.play($0, current: $1) },
                     artwork: { await YouTubeMusicQueueReader.artwork(for: $0) },
                     retriesWhenEmpty: true,
                     playNext: { try await YouTubeMusicQueueReader.playNext($0, current: $1) })
    }
}

enum QueueParsing {
    static let fieldSeparator: Character = "\u{1F}"

    /// Lines of `index US id US title US artist US duration`, as printed by `MusicQueueReader.script`.
    static func parse(_ output: String, limit: Int = 20) -> [QueueItem] {
        var items: [QueueItem] = []
        for line in output.split(whereSeparator: \.isNewline) {
            let fields = line.split(separator: fieldSeparator, omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 5, let index = Int(fields[0]), index > 0, !fields[1].isEmpty, !fields[2].isEmpty else { continue }
            items.append(QueueItem(index: index, persistentID: fields[1], title: String(fields[2].prefix(512)),
                                   artist: String(fields[3].prefix(512)), duration: Double(fields[4]) ?? 0))
            if items.count == limit { break }
        }
        return items
    }

    /// A row moved to the top, the rest keeping their order (the optimistic half of "Play Next").
    static func movingToTop(_ items: [QueueItem], id: String) -> [QueueItem] {
        guard let position = items.firstIndex(where: { $0.id == id }), position > 0 else { return items }
        var next = items
        next.insert(next.remove(at: position), at: 0)
        return next
    }
}

/// Reads and drives Apple Music's current playlist through Apple Events (public scripting API).
enum MusicQueueReader {
    /// Every variable carries a `q` prefix: inside `tell application "Music"`, `last` is a keyword
    /// ("last track") and `artists` a Music constant, so those bare names fail to compile
    /// ("Expected class name but found “to”.", "Can’t set «constant eSrAkSrR»").
    static func script(limit: Int) -> String {
        """
        tell application "Music"
          if player state is stopped then return ""
          set qList to current playlist
          set qTotal to count of tracks of qList
          set qCur to index of current track
          if qCur >= qTotal then return ""
          set qStop to qCur + \(limit)
          if qStop > qTotal then set qStop to qTotal
          set qRange to (tracks (qCur + 1) thru qStop of qList)
          set qTitles to name of qRange
          set qArtists to artist of qRange
          set qLengths to duration of qRange
          set qIDs to database ID of qRange
          set qSep to (ASCII character 31)
          set qOut to ""
          repeat with i from 1 to count of qTitles
            set qOut to qOut & (qCur + i) & qSep & (item i of qIDs) & qSep & (item i of qTitles) & qSep & (item i of qArtists) & qSep & (item i of qLengths) & linefeed
          end repeat
          return qOut
        end tell
        """
    }

    static func playScript(index: Int) -> String {
        "tell application \"Music\" to play (track \(index) of current playlist)"
    }

    static func artworkScript(index: Int) -> String {
        "tell application \"Music\" to get raw data of artwork 1 of (track \(index) of current playlist)"
    }

    private static let queue = DispatchQueue(label: "brim.music-queue", qos: .userInitiated)

    /// Cover bytes of one queued song, or nil when it has none (never throws for that).
    static func artwork(index: Int) async -> Data? {
        await withCheckedContinuation { continuation in
            queue.async {
                var error: NSDictionary?
                let result = NSAppleScript(source: artworkScript(index: index))?.executeAndReturnError(&error)
                let data = error == nil ? result?.data : nil
                continuation.resume(returning: (data?.count ?? 0) > 0 && (data?.count ?? 0) <= 3_000_000 ? data : nil)
            }
        }
    }

    static func run(_ source: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                var error: NSDictionary?
                let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
                if let error {
                    continuation.resume(throwing: NowPlayingFailure.unavailable(
                        (error[NSAppleScript.errorMessage] as? String) ?? "Apple Music did not answer."))
                } else { continuation.resume(returning: result?.stringValue ?? "") }
            }
        }
    }
}

/// "Playing Next": loads on demand, refreshes when the song changes, never polls.
@MainActor
final class PlayingNextModel: ObservableObject {
    static let shared = PlayingNextModel()
    @Published private(set) var items: [QueueItem] = []
    @Published private(set) var isLoading = false
    /// The last read failed (Music not answering, Automation denied). The column then shows its normal
    /// empty state; the underlying error is only logged, never shown.
    @Published private(set) var isUnavailable = false
    /// Chrome refuses JavaScript from Apple Events, so the YouTube Music page can't be read or
    /// clicked. Unlike other failures this one is shown: only the user can turn that setting on.
    @Published private(set) var needsChromeJavaScript = false
    private static let log = Logger(subsystem: "io.github.cezarprox.brim", category: "playing-next")
    /// Small covers for every row, by song id; loaded after the list so it never waits on them.
    @Published private(set) var artwork: [String: NSImage] = [:]
    private var artworkTask: Task<Void, Never>?
    private var loadedKey: String?
    private var task: Task<Void, Never>?
    private var music: QueueBackend
    private var youtube: QueueBackend
    /// The real backends while the filmed demo (`--demo`) answers with sample songs.
    private var demoOriginal: (music: QueueBackend, youtube: QueueBackend)?
    /// The backend of the song the list was last loaded for; covers and clicks go to it.
    private var active: QueueBackend?
    private var loadedSource: NowPlayingSource?

    init(music: QueueBackend = .appleMusic, youtube: QueueBackend = .youTubeMusic) {
        self.music = music
        self.youtube = youtube
    }

    /// A model answered by fixed closures for every source (onboarding samples, tests): it never
    /// reads a real player.
    convenience init(read: @escaping (Int) async throws -> String, perform: @escaping (String) async throws -> String,
                     fetchArtwork: @escaping (Int) async -> Data? = { _ in nil }) {
        let backend = QueueBackend.script(read: read, perform: perform, fetchArtwork: fetchArtwork)
        self.init(music: backend, youtube: backend)
    }

    /// The filmed demo: `backend` answers for every source (nil puts the real players back).
    func setDemoBackend(_ backend: QueueBackend?) {
        if let backend {
            if demoOriginal == nil { demoOriginal = (music, youtube) }
            music = backend
            youtube = backend
        } else if let original = demoOriginal {
            (music, youtube) = original
            demoOriginal = nil
        }
        task?.cancel()
        items = []
        artwork = [:]
        loadedKey = nil
        active = nil
        loadedSource = nil
    }

    private func backend(for source: NowPlayingSource?) -> QueueBackend? {
        guard QueueCapability.supportsQueue(source) else { return nil }
        return source == .music ? music : youtube
    }

    /// Reloads when the playing song changed since the last load (or `force`).
    func refresh(for track: NowPlayingTrack?, force: Bool = false) {
        guard let track, let backend = backend(for: track.snapshot.source) else {
            task?.cancel(); items = []; loadedKey = nil; isUnavailable = false; active = nil; loadedSource = nil
            return
        }
        let snapshot = track.snapshot
        let key = "\(snapshot.source.rawValue)\u{1F}\(track.title)\u{1F}\(track.artist)"
        guard force || key != loadedKey else { return }
        // Another player's list never shows under this one while it loads.
        if snapshot.source != loadedSource { items = [] }
        loadedKey = key
        loadedSource = snapshot.source
        active = backend
        task?.cancel()
        isLoading = items.isEmpty
        task = Task { [weak self] in
            do {
                let loaded = try await backend.read(snapshot, 12)
                guard !Task.isCancelled, let self else { return }
                items = loaded
                isUnavailable = false
                // A read can succeed through accessibility with page scripting still off, so only a
                // queue action that works clears `needsChromeJavaScript`.
                if loaded.isEmpty && backend.retriesWhenEmpty { loadedKey = nil }
                loadArtwork()
            } catch {
                guard !Task.isCancelled, let self else { return }
                Self.log.error("Playing Next read failed: \(error.localizedDescription, privacy: .public)")
                items = []
                isUnavailable = true
                needsChromeJavaScript = Self.isChromeJavaScriptOff(error)
                loadedKey = nil
            }
            self?.isLoading = false
        }
    }

    private func loadArtwork() {
        artworkTask?.cancel()
        // Every row the list holds (a read is capped at 12): scrolling down must not reveal blank covers.
        let wanted = items.filter { artwork[$0.persistentID] == nil }
        guard !wanted.isEmpty, let backend = active else { return }
        artworkTask = Task { [weak self] in
            for item in wanted {
                guard !Task.isCancelled else { return }
                guard let data = await backend.artwork(item),
                      let image = await Task.detached(priority: .utility, operation: { Self.thumbnail(data) }).value
                else { continue }
                self?.artwork[item.persistentID] = image
            }
        }
    }

    nonisolated private static func thumbnail(_ data: Data) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 96,
                kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceShouldCacheImmediately: true,
              ] as CFDictionary) else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }

    // MARK: Play Next

    /// Neither Apple Music nor YouTube Music lets another app reorder their Up Next, so "Play Next"
    /// is kept here: the pick waits until the song changes on its own (end, skip from anywhere),
    /// then Brim starts it. Choosing a different song in the player cancels it.
    private struct Pick {
        let item: QueueItem
        /// The song that was going to play next, so a natural advance can be told from a choice.
        let natural: QueueItem?
        let fromSongKey: String
        let source: NowPlayingSource
    }
    private var pick: Pick?
    /// The song playing when the player itself queued `pendingNext`.
    private var nativeFromSongKey: String?
    @Published private(set) var pendingNext: QueueItem?

    @discardableResult
    func playNext(_ item: QueueItem, track: NowPlayingTrack?) -> Task<Void, Never>? {
        guard let track, let backend = backend(for: track.snapshot.source) else { return nil }
        if let native = backend.playNext {
            clearPick()
            nativeFromSongKey = track.songKey
            pendingNext = item
            items = QueueParsing.movingToTop(items, id: item.id)
            return Task { [weak self] in
                do {
                    try await native(item, track.snapshot)
                    self?.needsChromeJavaScript = false
                } catch {
                    Self.log.error("Play next failed: \(error.localizedDescription, privacy: .public)")
                    guard let self else { return }
                    needsChromeJavaScript = Self.isChromeJavaScriptOff(error)
                    pendingNext = nil
                    nativeFromSongKey = nil
                    refresh(for: track, force: true)
                }
            }
        }
        let natural = items.first.flatMap { $0.id == item.id ? nil : $0 }
        pick = Pick(item: item, natural: natural, fromSongKey: track.songKey, source: track.snapshot.source)
        pendingNext = item
        items = QueueParsing.movingToTop(items, id: item.id)
        return nil
    }

    /// Called on every Now Playing change. Starts the pick when the player moved on by itself.
    @discardableResult
    func trackChanged(_ track: NowPlayingTrack?) -> Task<Void, Never>? {
        // A pick the player queued itself is done once the song moves on.
        if let from = nativeFromSongKey, let track, track.songKey != from {
            nativeFromSongKey = nil
            pendingNext = nil
        }
        guard let pick, let track, track.songKey != pick.fromSongKey else { return nil }
        clearPick()
        guard track.snapshot.source == pick.source, !Self.matches(track, pick.item),
              pick.natural.map({ Self.matches(track, $0) }) ?? true else { return nil }
        return start(pick.item, snapshot: track.snapshot, track: track)
    }

    /// The island's skip: with a pick waiting, go straight to it instead of the player's next song.
    @discardableResult
    /// When the player won't start the pick (its row is no longer on the page), `fallback` runs the
    /// ordinary skip, so a press of Next is never lost.
    func skipToPending(from track: NowPlayingTrack?, fallback: (() -> Void)? = nil) -> Task<Void, Never>? {
        guard let pick, let track, track.songKey == pick.fromSongKey, track.snapshot.source == pick.source else { return nil }
        clearPick()
        return start(pick.item, snapshot: track.snapshot, track: track, onFailure: fallback)
    }

    private func clearPick() {
        pick = nil
        pendingNext = nil
        nativeFromSongKey = nil
    }

    private func start(_ item: QueueItem, snapshot: NowPlayingSnapshot, track: NowPlayingTrack,
                       onFailure: (() -> Void)? = nil) -> Task<Void, Never>? {
        guard let backend = backend(for: snapshot.source) else { return nil }
        return Task { [weak self] in
            do {
                try await backend.play(item, snapshot)
                self?.needsChromeJavaScript = false
            } catch {
                Self.log.error("Playing Next pick failed: \(error.localizedDescription, privacy: .public)")
                // Same hint as Play Next: say why, instead of a row that silently does nothing.
                self?.needsChromeJavaScript = Self.isChromeJavaScriptOff(error)
                onFailure?()
                self?.refresh(for: track, force: true)
            }
        }
    }

    /// Chrome's AppleScript error when View › Developer › Allow JavaScript from Apple Events is off.
    static func isChromeJavaScriptOff(_ error: Error) -> Bool {
        let text = error.localizedDescription
        return text.contains("JavaScript through AppleScript is turned off") || text.contains("Allow JavaScript from Apple Events")
    }

    static func matches(_ track: NowPlayingTrack, _ item: QueueItem) -> Bool {
        let fold = { (text: String) in text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespaces) }
        guard fold(track.title) == fold(item.title) else { return false }
        return item.artist.isEmpty || track.artist.isEmpty || fold(track.artist) == fold(item.artist)
    }

    /// Jumps to a row: it moves to the top at once, then the player starts it.
    func playNow(_ item: QueueItem, track: NowPlayingTrack?) {
        clearPick()
        guard let snapshot = track?.snapshot, let backend = backend(for: snapshot.source) else { return }
        items = QueueParsing.movingToTop(items, id: item.id)
        Task { [weak self] in
            do {
                try await backend.play(item, snapshot)
                self?.needsChromeJavaScript = false
            } catch {
                Self.log.error("Playing Next jump failed: \(error.localizedDescription, privacy: .public)")
                self?.needsChromeJavaScript = Self.isChromeJavaScriptOff(error)
                // Undo the optimistic move by reading the real queue again.
                self?.refresh(for: track, force: true)
                return
            }
            self?.loadedKey = nil
        }
    }
}
