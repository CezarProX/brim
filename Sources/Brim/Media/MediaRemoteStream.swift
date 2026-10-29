import Foundation

/// One line of the helper's output (`brim-mediaremote.pl <dylib> stream`).
enum MediaRemoteStreamMessage: Equatable, Sendable {
    case nowPlaying(Payload)
    case none
    case reply(id: Int, result: String)
    case unavailable

    struct Payload: Equatable, Sendable {
        var bundle: String
        var title: String
        var artist: String
        var album: String
        var duration: TimeInterval
        /// Elapsed time at `timestamp`; the song has advanced at `rate` since.
        var elapsed: TimeInterval
        var rate: Double
        var timestamp: Date
        var isPlaying: Bool
        var artwork: Data?
    }

    /// Lines over this size are dropped rather than parsed (artwork is capped at 4 MB raw).
    static let maxLineBytes = 6_000_000

    static func parse(_ line: String) -> MediaRemoteStreamMessage? {
        guard line.utf8.count <= maxLineBytes, let data = line.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let type = object["type"] as? String else { return nil }
        switch type {
        case "none": return MediaRemoteStreamMessage.none
        case "unavailable": return .unavailable
        case "reply":
            guard let id = object["id"] as? Int, let result = object["result"] as? String else { return nil }
            return .reply(id: id, result: result)
        case "nowplaying":
            guard let bundle = object["bundle"] as? String, let title = object["title"] as? String,
                  !bundle.isEmpty, !title.isEmpty else { return nil }
            func number(_ key: String) -> Double {
                let value = (object[key] as? NSNumber)?.doubleValue ?? 0
                return value.isFinite ? value : 0
            }
            let stamp = number("timestamp")
            return .nowPlaying(Payload(
                bundle: bundle, title: String(title.prefix(2048)),
                artist: String((object["artist"] as? String ?? "").prefix(2048)),
                album: String((object["album"] as? String ?? "").prefix(2048)),
                duration: max(0, number("duration")), elapsed: max(0, number("elapsed")),
                rate: number("rate"), timestamp: stamp > 0 ? Date(timeIntervalSince1970: stamp) : Date(),
                isPlaying: (object["playing"] as? Bool) ?? false,
                artwork: (object["artwork"] as? String).flatMap { Data(base64Encoded: $0) }))
        default: return nil
        }
    }
}

extension MediaRemoteStreamMessage.Payload {
    /// The app that owns a MediaRemote session, as one of Brim's sources.
    static func source(forBundle bundle: String) -> NowPlayingSource? {
        NowPlayingSource.allCases.first { !$0.isBrowser && $0.bundleID == bundle }
            ?? (bundle.hasPrefix("com.google.Chrome.app.") ? .youtubeApp : nil)
    }

    func snapshot(source: NowPlayingSource, previous: NowPlayingSnapshot?) -> NowPlayingSnapshot {
        let sameSong = previous.map { $0.source == source && $0.title == title && $0.artist == artist } ?? false
        var snapshot = NowPlayingSnapshot(
            source: source, title: title, artist: artist, album: album, duration: duration,
            position: elapsed, isPlaying: isPlaying, artworkData: artwork,
            isFavorite: sameSong ? previous?.isFavorite : nil, isShuffling: sameSong ? previous?.isShuffling : nil)
        snapshot.playbackRate = rate
        if sameSong { snapshot.pageURL = previous?.pageURL }
        return snapshot
    }
}

/// Splits a byte stream into lines without ever holding more than `limit` bytes.
struct LineBuffer: Sendable {
    private var pending = Data()
    let limit: Int
    init(limit: Int = MediaRemoteStreamMessage.maxLineBytes) { self.limit = limit }

    mutating func feed(_ data: Data) -> [String] {
        pending.append(data)
        var lines: [String] = []
        while let newline = pending.firstIndex(of: 0x0A) {
            let line = pending[pending.startIndex..<newline]
            if line.count <= limit, let text = String(data: line, encoding: .utf8), !text.isEmpty { lines.append(text) }
            pending.removeSubrange(pending.startIndex...newline)
        }
        if pending.count > limit { pending.removeAll() } // an over-long line with no end: drop it
        return lines
    }
}

/// The long-lived helper: now-playing changes arrive as events and commands go over its stdin,
/// so nothing polls and a play/pause costs one pipe write instead of a process launch.
final class MediaRemoteStreamClient: @unchecked Sendable {
    typealias Handler = @Sendable (MediaRemoteStreamMessage) -> Void
    private let helper: NowPlayingMediaRemote.Helper
    private let lock = NSLock()
    private var process: Process?
    private var input: FileHandle?
    private var buffer = LineBuffer()
    private var nextID = 1
    private var waiting: [Int: CheckedContinuation<String?, Never>] = [:]
    private var handler: Handler?
    private var restartsLeft = 4

    init(helper: NowPlayingMediaRemote.Helper) { self.helper = helper }

    var isRunning: Bool { lock.withLock { process?.isRunning == true } }

    func start(_ handler: @escaping Handler) {
        lock.withLock { self.handler = handler; restartsLeft = 4 }
        launch()
    }

    private func launch() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [helper.script.path, helper.library.path, "stream"]
        let stdin = Pipe(), stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil; return }
            self?.receive(data)
        }
        process.terminationHandler = { [weak self] finished in self?.terminated(finished) }
        do { try process.run() } catch { handle(.unavailable); return }
        lock.withLock { self.process = process; input = stdin.fileHandleForWriting; buffer = LineBuffer() }
    }

    private func receive(_ data: Data) {
        let lines = lock.withLock { buffer.feed(data) }
        for line in lines {
            guard let message = MediaRemoteStreamMessage.parse(line) else { continue }
            if case .reply(let id, let result) = message {
                lock.withLock { waiting.removeValue(forKey: id) }?.resume(returning: result)
            } else { handle(message) }
        }
    }

    private func handle(_ message: MediaRemoteStreamMessage) {
        let handler = lock.withLock { self.handler }
        handler?(message)
    }

    private func terminated(_ finished: Process) {
        let (pending, again) = lock.withLock { () -> ([CheckedContinuation<String?, Never>], Bool) in
            guard process === finished else { return ([], false) }
            process = nil; input = nil
            let all = Array(waiting.values); waiting.removeAll()
            let retry = handler != nil && restartsLeft > 0
            if retry { restartsLeft -= 1 }
            return (all, retry)
        }
        pending.forEach { $0.resume(returning: nil) }
        if again {
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [weak self] in
                guard let self, self.lock.withLock({ self.handler != nil && self.process == nil }) else { return }
                self.launch()
            }
        } else { handle(.unavailable) }
    }

    func stop() {
        let (process, input) = lock.withLock { () -> (Process?, FileHandle?) in
            handler = nil
            defer { self.process = nil; self.input = nil }
            return (self.process, self.input)
        }
        try? input?.close()
        process?.terminate()
    }

    /// "sent 0", "notfound", "invalid", or nil when the helper is not running / did not answer.
    func request(_ line: (Int) -> String, timeout: TimeInterval = 4) async -> String? {
        let id = lock.withLock { () -> Int in defer { nextID += 1 }; return nextID }
        guard let input = lock.withLock({ self.input }) else { return nil }
        return await withCheckedContinuation { continuation in
            lock.withLock { waiting[id] = continuation }
            do { try input.write(contentsOf: Data((line(id) + "\n").utf8)) }
            catch { lock.withLock { waiting.removeValue(forKey: id) }?.resume(returning: nil); return }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [weak self] in
                self?.lock.withLock { self?.waiting.removeValue(forKey: id) }?.resume(returning: nil)
            }
        }
    }

    func send(command: Int32, bundleID: String) async -> String? {
        await request { "send \($0) \(command) \(bundleID)" }
    }

    /// Seeks `bundleID`'s player; the helper answers "notnowplaying" when that isn't macOS's now-playing app.
    func seek(to seconds: TimeInterval, bundleID: String) async -> String? {
        await request { "seek \($0) \(seconds) \(bundleID)" }
    }
}
