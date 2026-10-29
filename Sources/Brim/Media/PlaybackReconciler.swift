import Foundation

/// Where playback is at `date`, from one sample: `position` was true at `anchor` and the
/// song has advanced at `rate` since. This is how MediaRemote reports elapsed time
/// (elapsed + timestamp + playbackRate), so a steady song needs no polling to stay smooth.
struct ElapsedClock: Equatable, Sendable {
    var position: TimeInterval
    var anchor: Date
    var rate: Double
    var duration: TimeInterval
    /// Stop extrapolating this long after the anchor (polled sources whose samples may stall).
    var stallCap: TimeInterval?

    func position(at date: Date) -> TimeInterval {
        guard position.isFinite, rate.isFinite else { return 0 }
        var elapsed = max(0, date.timeIntervalSince(anchor))
        if let stallCap { elapsed = min(stallCap, elapsed) }
        let value = max(0, position + elapsed * rate)
        return duration > 0 ? min(duration, value) : value
    }
}

/// What the UI shows right after a control is used, before the player confirms it.
///
/// Controls flip the UI immediately (play/pause icon, frozen or running elapsed time, a
/// skeleton for next/previous). Each pending intent is reconciled against real samples:
/// confirmed when the source agrees, rolled back when it still contradicts after `grace`,
/// dropped at once when the command itself fails.
struct OptimisticPlayback: Equatable, Sendable {
    static let grace: TimeInterval = 1.5
    /// A play/pause is not confirmed sooner than this, so a quick pause-then-play is not
    /// "confirmed" by a sample that predates the first tap.
    static let settle: TimeInterval = 0.3

    struct Play: Equatable, Sendable { var wantsPlaying: Bool; var since: Date; var frozenPosition: TimeInterval }
    struct Seek: Equatable, Sendable { var target: TimeInterval; var since: Date; var wasPlaying: Bool }
    struct Skip: Equatable, Sendable { var forward: Bool; var fromKey: String; var since: Date }
    struct Flag: Equatable, Sendable { var value: Bool; var since: Date }
    struct RepeatIntent: Equatable, Sendable { var value: RepeatMode; var since: Date }

    var play: Play?
    var seek: Seek?
    var skip: Skip?
    var favorite: Flag?
    var shuffle: Flag?
    var repeatMode: RepeatIntent?

    enum Event: Equatable, Sendable { case confirmed, rolledBack }

    var isEmpty: Bool { play == nil && seek == nil && skip == nil && favorite == nil && shuffle == nil && repeatMode == nil }
    /// Earliest moment a pending intent can expire, so the model can schedule one tick.
    var nextDeadline: Date? {
        [play?.since, seek?.since, skip?.since, favorite?.since, shuffle?.since, repeatMode?.since].compactMap { $0 }
            .min().map { $0.addingTimeInterval(Self.grace) }
    }

    static func key(_ snapshot: NowPlayingSnapshot) -> String {
        "\(snapshot.source.rawValue)\u{1F}\(snapshot.title)\u{1F}\(snapshot.artist)"
    }

    // MARK: Intents

    /// Returns the new wanted state: the opposite of what is displayed right now.
    @discardableResult
    mutating func togglePlayPause(displayed: NowPlayingSnapshot, position: TimeInterval, now: Date) -> Bool {
        let wants = !displayed.isPlaying
        play = Play(wantsPlaying: wants, since: now, frozenPosition: position)
        return wants
    }

    mutating func startSeek(to target: TimeInterval, displayed: NowPlayingSnapshot, now: Date) {
        seek = Seek(target: target, since: now, wasPlaying: displayed.isPlaying)
    }

    /// Previous past the first seconds restarts the song, like every player: no skeleton.
    static let restartThreshold: TimeInterval = 3

    mutating func startSkip(forward: Bool, displayed: NowPlayingSnapshot, position: TimeInterval, now: Date) {
        if !forward, position > Self.restartThreshold {
            seek = Seek(target: 0, since: now, wasPlaying: displayed.isPlaying)
            return
        }
        skip = Skip(forward: forward, fromKey: Self.key(displayed), since: now)
        seek = nil
    }

    mutating func setFavorite(_ value: Bool, now: Date) { favorite = Flag(value: value, since: now) }
    mutating func setShuffle(_ value: Bool, now: Date) { shuffle = Flag(value: value, since: now) }
    mutating func setRepeat(_ value: RepeatMode, now: Date) { repeatMode = RepeatIntent(value: value, since: now) }

    /// The command failed outright: show the source's truth again immediately.
    mutating func fail() { self = OptimisticPlayback() }

    // MARK: Reconciliation

    /// Compares each pending intent with a fresh sample (nil = nothing playing).
    @discardableResult
    mutating func reconcile(observed: NowPlayingSnapshot?, position: TimeInterval, now: Date) -> [Event] {
        var events: [Event] = []
        func expired(_ since: Date) -> Bool { now.timeIntervalSince(since) >= Self.grace }
        func settled(_ since: Date) -> Bool { now.timeIntervalSince(since) >= Self.settle }
        guard let observed else {
            if !isEmpty { events.append(.rolledBack) }
            self = OptimisticPlayback()
            return events
        }
        if let play {
            if observed.isPlaying == play.wantsPlaying, settled(play.since) { events.append(.confirmed); self.play = nil }
            else if expired(play.since) { events.append(.rolledBack); self.play = nil }
        }
        if let seek {
            let expected = seek.target + (observed.isPlaying && seek.wasPlaying ? now.timeIntervalSince(seek.since) : 0)
            if abs(observed.position - expected) <= 2.5 { events.append(.confirmed); self.seek = nil }
            else if expired(seek.since) { events.append(.rolledBack); self.seek = nil }
        }
        if let skip {
            if Self.key(observed) != skip.fromKey { events.append(.confirmed); self.skip = nil }
            else if expired(skip.since) { events.append(.rolledBack); self.skip = nil }
        }
        if let favorite {
            if observed.isFavorite == favorite.value { events.append(.confirmed); self.favorite = nil }
            else if expired(favorite.since) { events.append(.rolledBack); self.favorite = nil }
        }
        if let shuffle {
            if observed.isShuffling == shuffle.value { events.append(.confirmed); self.shuffle = nil }
            else if expired(shuffle.since) { events.append(.rolledBack); self.shuffle = nil }
        }
        if let repeatMode {
            if observed.repeatMode == repeatMode.value { events.append(.confirmed); self.repeatMode = nil }
            else if expired(repeatMode.since) { events.append(.rolledBack); self.repeatMode = nil }
        }
        return events
    }

    // MARK: Display

    struct Display: Equatable, Sendable {
        var snapshot: NowPlayingSnapshot
        /// When `snapshot.position` was true (the clock's anchor).
        var anchor: Date?
        var isTransitioning: Bool
    }

    /// The real sample with pending intents laid over it. `sampleAnchor` is when the real
    /// position was true; the overlay re-anchors only when it changes the position.
    func apply(to observed: NowPlayingSnapshot, sampleAnchor: Date, now: Date) -> Display {
        var display = Display(snapshot: observed, anchor: sampleAnchor, isTransitioning: false)
        var position = observed.position
        var playing = observed.isPlaying
        var anchor = sampleAnchor
        if let play {
            playing = play.wantsPlaying
            position = play.frozenPosition
            anchor = play.since
        }
        if let seek {
            position = seek.target
            anchor = seek.since
            if play == nil { playing = observed.isPlaying }
        }
        if let skip, skip.forward || seek == nil {
            position = 0
            anchor = skip.since
            display.isTransitioning = true
        }
        if play != nil || seek != nil || skip != nil {
            display.snapshot = observed.replacing(isPlaying: playing, position: position)
            display.anchor = anchor
        }
        if let favorite { display.snapshot = display.snapshot.replacing(isFavorite: favorite.value) }
        if let shuffle { display.snapshot = display.snapshot.replacing(isShuffling: shuffle.value) }
        if let repeatMode { display.snapshot = display.snapshot.replacing(repeatMode: repeatMode.value) }
        return display
    }
}

extension NowPlayingSnapshot {
    /// A copy with some fields replaced (the type's stored properties are `let`).
    func replacing(isPlaying: Bool? = nil, position: TimeInterval? = nil,
                   isFavorite: Bool? = nil, isShuffling: Bool? = nil, repeatMode: RepeatMode? = nil,
                   artworkData: Data?? = nil) -> NowPlayingSnapshot {
        var copy = NowPlayingSnapshot(
            source: source, title: title, artist: artist, album: album, duration: duration,
            position: position ?? self.position, isPlaying: isPlaying ?? self.isPlaying,
            artworkData: artworkData ?? self.artworkData, artworkURL: artworkURL, albumURL: albumURL,
            isFavorite: isFavorite ?? self.isFavorite, isShuffling: isShuffling ?? self.isShuffling)
        copy.pageURL = pageURL
        copy.artistURL = artistURL
        copy.playbackRate = playbackRate
        copy.repeatMode = repeatMode ?? self.repeatMode
        return copy
    }
}
