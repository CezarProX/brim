import AppKit
import Combine
import ImageIO
import os

@MainActor
final class NowPlayingModel: ObservableObject {
    static let shared = NowPlayingModel(resumeStore: .standard)
    @Published private(set) var track: NowPlayingTrack?
    /// Shown while nothing is playing and no access problem needs attention.
    static let idleStatus = "Music you play appears here automatically."
    @Published private(set) var status = NowPlayingModel.idleStatus
    @Published private(set) var commandError: String?
    @Published private(set) var isConnecting = false
    @Published private(set) var isBusy = false
    @Published private(set) var enabledSources: [NowPlayingSource]
    @Published private(set) var sourceStatus: [NowPlayingSource: String] = [:]
    @Published private(set) var accessSource: NowPlayingSource?
    var isConnected: Bool { !enabledSources.isEmpty }
    /// Like iOS, a song paused here keeps its island place for a while instead of vanishing at once.
    /// Settings > Media > "Hide on pause"; 0 minutes keeps a paused song until its player is gone.
    static var pausedIslandDuration: TimeInterval {
        let minutes = AppSettings.shared.mediaHideOnPauseMinutes
        return minutes == 0 ? .infinity : TimeInterval(minutes) * 60
    }
    /// When the current song went from playing to paused; nil while playing or never seen playing.
    private(set) var pausedAt: Date?
    /// The last song heard, kept after its player quits so it can be resumed at the same second.
    @Published private(set) var lastPlayed: NowPlayingResume.LastPlayed?
    @Published private(set) var lastArtwork: NSImage?
    /// Play was pressed with no song on screen and macOS has not reported one yet: the UI shows the
    /// song as starting (the button already flipped) until the stream delivers it or this times out.
    @Published private(set) var isStartingPlayback = false
    private var idlePlayTask: Task<Void, Never>?
    private var idlePlayActions: NowPlayingIdlePlay.Actions?
    private var resumeStore: NowPlayingResume.Store
    private var lastSaved = Date.distantPast
    private var pendingLast: NowPlayingResume.LastPlayed?
    /// The cover last written to the resume store, so steady polling never rewrites the file.
    private var savedArtwork: NSImage?

    func isInIsland(now: Date = .now) -> Bool {
        guard let track, MediaVisibility.shared.allows(track) else { return false }
        if track.isPlaying { return true }
        return pausedAt.map { now.timeIntervalSince($0) <= Self.pausedIslandDuration } ?? false
    }

    private var provider: any NowPlayingProviding
    private let persist: ([NowPlayingSource]) -> Void
    private var fixedSources: [NowPlayingSource]?
    private var pollingTask: Task<Void, Never>?
    private var artworkTask: Task<Void, Never>?
    private var generation = 0
    private var artworkKey: String?
    private var artworkRetryAt = Date.distantPast
    private let artworkLoader: (NowPlayingSnapshot) async -> Data?
    private let artworkNow: () -> Date
    private var actionToken = NowPlayingActionToken()
    private var isRefreshing = false
    /// The last real sample, before any optimistic overlay; `track` is what the UI shows.
    private var observed: NowPlayingSnapshot?
    private var observedAnchor = Date()
    private var overlay = OptimisticPlayback()
    private var displayAnchor = Date()
    private var displayTransitioning = false
    private var lastCommandIssuedAt = Date.distantPast
    private var commandChain: Task<Void, Never>?
    private var deadlineTask: Task<Void, Never>?
    private var nudgeTask: Task<Void, Never>?
    private var stream: MediaRemoteStreamClient?
    /// The real sources while the filmed demo (`--demo`) plays sample songs; see `enterDemo`.
    private var demoOriginal: DemoOriginal?
    /// True while the event-driven helper is delivering, so polling can relax.
    private(set) var streamAlive = false
    /// Empty reads in a row. The player clears only on the second, so a hiccup between songs
    /// (or a page mid-navigation) does not blink the island empty.
    private var emptyReads = 0

    init(provider: any NowPlayingProviding = NowPlayingProvider(), enabledSources: [NowPlayingSource]? = nil,
         persist: @escaping ([NowPlayingSource]) -> Void = { _ in },
         artworkLoader: @escaping (NowPlayingSnapshot) async -> Data? = { await NowPlayingArtwork.load($0) },
         artworkNow: @escaping () -> Date = Date.init,
         resumeStore: NowPlayingResume.Store = .ephemeral,
         stream: MediaRemoteStreamClient? = NowPlayingMediaRemote.stream,
         idlePlay: NowPlayingIdlePlay.Actions? = nil) {
        self.stream = stream
        self.idlePlayActions = idlePlay
        self.resumeStore = resumeStore
        self.lastPlayed = resumeStore.load()
        let savedArtwork = resumeStore.artwork().flatMap(NSImage.init(data:))
        self.lastArtwork = savedArtwork
        self.savedArtwork = savedArtwork
        self.artworkLoader = artworkLoader
        self.artworkNow = artworkNow
        self.provider = provider
        self.enabledSources = enabledSources ?? []
        self.fixedSources = enabledSources
        self.persist = persist
    }

    func start() {
        guard pollingTask == nil else { return }
        stream?.start { [weak self] message in
            Task { @MainActor [weak self] in self?.handleStream(message) }
        }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshNow()
                // Events carry the changes while the stream helper lives; polling only backstops
                // it (and serves browsers). Without the stream, poll often enough to feel live.
                let streaming = await self?.streamAlive == true
                let playing = await self?.track?.isPlaying == true
                let seconds: Double = streaming ? (playing ? 4 : 6) : (playing ? 1 : 2)
                do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
            }
        }
    }

    func stop() {
        generation += 1
        actionToken.invalidate()
        actionToken = NowPlayingActionToken()
        pollingTask?.cancel()
        pollingTask = nil
        stream?.stop()
        streamAlive = false
        deadlineTask?.cancel()
        nudgeTask?.cancel()
        commandChain = nil
        overlay = OptimisticPlayback()
        artworkTask?.cancel()
        artworkTask = nil
        artworkRetryAt = .distantPast
        idlePlayTask?.cancel()
        isStartingPlayback = false
    }

    /// Discovery is automatic. Only an explicit Enable access action can request OS consent.
    func enableAccess() {
        guard let source = accessSource else { return }
        if source == .youtubeApp {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        } else { connect(source) }
    }

    func connect(_ source: NowPlayingSource = .music) {
        guard !isBusy else { return }
        generation += 1
        isBusy = true
        isConnecting = true
        status = "Allow access to \(source.name) in the macOS prompt…"
        let token = actionToken
        Task {
            defer { isBusy = false; isConnecting = false }
            do {
                try await provider.connect(source)
                guard token.isValid else { return }
                if !enabledSources.contains(source) { enabledSources.append(source) }
                persist(enabledSources)
                sourceStatus[source] = "Connected"
                accessSource = nil
                status = "Access enabled. Your music will appear automatically."
            } catch {
                guard token.isValid else { return }
                sourceStatus[source] = error.localizedDescription
                status = error.localizedDescription
            }
        }
    }

    func disconnect(_ source: NowPlayingSource) {
        generation += 1
        actionToken.invalidate()
        actionToken = NowPlayingActionToken()
        enabledSources.removeAll { $0 == source }
        fixedSources?.removeAll { $0 == source }
        sourceStatus.removeValue(forKey: source)
        persist(enabledSources)
        if track?.snapshot.source == source { ingest(nil, anchor: Date()) }
        status = Self.idleStatus
    }

    func refresh() { Task { await refreshNow() } }

    func refreshNow() async {
        guard !isBusy, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let startedAt = artworkNow()
        let refreshGeneration = generation
        let sources: [NowPlayingSource]
        if let fixedSources { sources = fixedSources }
        else { sources = await provider.runningSources() }
        guard refreshGeneration == generation, !Task.isCancelled else { return }
        if enabledSources != sources { enabledSources = sources }
        var nextAccessSource: NowPlayingSource?
        var nextSourceStatus = sourceStatus
        var candidates: [NowPlayingSnapshot] = []
        var failures: [String] = []
        for source in sources {
            do {
                if let snapshot = try await provider.snapshot(source) { candidates.append(snapshot) }
                guard refreshGeneration == generation, !Task.isCancelled else { return }
                nextSourceStatus[source] = "Connected"
                if candidates.last?.isPlaying == true { break }
            } catch {
                guard refreshGeneration == generation, !Task.isCancelled else { return }
                nextSourceStatus[source] = error.localizedDescription
                // A browser being open doesn't mean YouTube Music is in it: its setup errors belong in
                // Settings → Connections, not in place of the player.
                guard !source.isBrowser else { continue }
                failures.append(error.localizedDescription)
                if nextAccessSource == nil, let failure = error as? NowPlayingFailure {
                    switch failure {
                    case .permission, .accessibility: nextAccessSource = source
                    default: break
                    }
                }
            }
            guard refreshGeneration == generation, !Task.isCancelled else { return }
        }
        let rawSelected = candidates.first(where: { $0.isPlaying })
            ?? candidates.first(where: { $0.source == track?.snapshot.source }) ?? candidates.first
        // A read that began before the latest control press may predate it: drop it, the next
        // sample (or the press's own confirmation poll) is authoritative.
        guard startedAt >= lastCommandIssuedAt else { return }
        if let rawSelected, isLaggingAppPoll(rawSelected) { return }
        let selected = rawSelected.map(reconcilingPoll)
        // A player that quit is certainly gone; only a still-running one gets the second look.
        if selected == nil, failures.isEmpty, !sources.isEmpty, observed != nil, emptyReads == 0 {
            emptyReads = 1
            return
        }
        emptyReads = 0
        ingest(selected, anchor: Date())
        if let selected { remember(selected) }
        else if let pendingLast, lastPlayed != pendingLast {
            // The player went away: Recently Played resumes from where it last was.
            lastPlayed = pendingLast
            persist(pendingLast)
        }
        if selected != nil { nextAccessSource = nil }
        if accessSource != nextAccessSource { accessSource = nextAccessSource }
        if sourceStatus != nextSourceStatus { sourceStatus = nextSourceStatus }
        let nextStatus = commandError ?? (selected == nil
            ? (failures.first ?? "Nothing playing. Start a song — Brim detects it automatically.") : "")
        if status != nextStatus { status = nextStatus }
    }

    /// Keeps the song for Recently Played. Position is tracked privately and published only when the
    /// song changes or its player goes away, so steady polling never re-renders the notch.
    private func remember(_ snapshot: NowPlayingSnapshot) {
        var next = NowPlayingResume.LastPlayed(
            source: snapshot.source, title: snapshot.title, artist: snapshot.artist, album: snapshot.album,
            duration: snapshot.duration, position: snapshot.position, pageURL: snapshot.pageURL,
            artworkURL: snapshot.artworkURL.flatMap { NowPlayingSnapshot.safeArtworkURL($0)?.absoluteString },
            savedAt: artworkNow())
        let songChanged = pendingLast?.title != next.title || pendingLast?.artist != next.artist
        if next.artworkURL == nil, !songChanged { next.artworkURL = pendingLast?.artworkURL }
        pendingLast = next
        if songChanged {
            lastPlayed = next
            lastArtwork = track?.artwork
        } else if lastArtwork == nil, let artwork = track?.artwork {
            lastArtwork = artwork
        }
        let now = artworkNow()
        guard songChanged || !snapshot.isPlaying || now.timeIntervalSince(lastSaved) >= 10 else { return }
        lastSaved = now
        persist(next)
    }

    /// Saves the song with a local copy of its cover, rewritten only when the cover changes. Thumbnails are
    /// kept too: offline, or when YouTube has no maxres image, Recently Played still shows the cover.
    private func persist(_ last: NowPlayingResume.LastPlayed) {
        resumeStore.save(last)
        guard savedArtwork !== lastArtwork else { return }
        savedArtwork = lastArtwork
        resumeStore.replaceArtwork(lastArtwork?.tiffRepresentation
            .flatMap(NSBitmapImageRep.init(data:))?.representation(using: .png, properties: [:]))
    }

    /// Recently Played's Play: the same as `playFromIdle`. It used to relaunch the player at the saved
    /// page (for YouTube Music, a new app window), which is not what the Mac's play key does.
    func resume() { playFromIdle() }

    /// Play with no song on screen, like the Mac's play key: macOS resumes whatever last played, in
    /// place. The button flips at once; a second press before the song shows up pauses again.
    func playFromIdle() {
        if track != nil { command(.playPause); return }
        let actions = idlePlayActions ?? NowPlayingIdlePlay.live(for: self)
        idlePlayTask?.cancel()
        if isStartingPlayback {
            isStartingPlayback = false
            // Pause where the play went, never whatever else macOS calls now playing.
            let player = NowPlayingIdlePlay.runningPlayer(lastPlayed: lastPlayed?.source, actions: actions)
            idlePlayTask = Task {
                if let player { _ = try? await actions.sendToPlayer(NowPlayingIdlePlay.pause, player) }
                else { _ = try? await actions.sendToSystem(NowPlayingIdlePlay.pause) }
            }
            return
        }
        isStartingPlayback = true
        commandError = nil
        let source = lastPlayed?.source
        Self.controlsLog.notice("idle play last=\(source?.rawValue ?? "none", privacy: .public)")
        idlePlayTask = Task { [weak self] in
            let outcome = await NowPlayingIdlePlay.run(lastPlayed: source, actions: actions)
            guard !Task.isCancelled, let self else { return }
            switch outcome {
            case .started:
                // The song normally arrives within the run; give a slow player a little longer.
                if track?.isPlaying != true { _ = await waitForPlayback(timeout: 2.5) }
                guard !Task.isCancelled else { return }
            case .failed(let message):
                commandError = message
                status = message
            }
            isStartingPlayback = false
        }
    }

    /// True once a playing song is on screen, within `timeout`. Reads the players itself while the
    /// stream (which would report it as an event) is not running.
    func waitForPlayback(timeout: TimeInterval) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(timeout)
        while track?.isPlaying != true {
            guard !Task.isCancelled, ContinuousClock.now < deadline else { return false }
            if !streamAlive { await refreshNow() }
            if track?.isPlaying == true { break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return true
    }

    func toggleFavorite() {
        guard let favorite = track?.snapshot.isFavorite else { return }
        command(.setFavorite(!favorite))
    }

    func toggleShuffle() {
        guard let shuffling = track?.snapshot.isShuffling else { return }
        command(.setShuffle(!shuffling))
    }

    /// Cycles off, all, one (Apple Music) or off, all (Spotify).
    func cycleRepeat() {
        guard let snapshot = track?.snapshot, let current = snapshot.repeatMode else { return }
        command(.setRepeat(current.next(supportsOne: RepeatMode.supportsOne(snapshot.source))))
    }

    func playPause() { command(.playPause) }
    /// A "Play Next" pick from the island's queue wins over the player's own next song.
    func next() {
        if self === NowPlayingModel.shared,
           PlayingNextModel.shared.skipToPending(from: track, fallback: { [weak self] in self?.command(.next) }) != nil { return }
        command(.next)
    }
    func previous() { command(.previous) }

    func seek(to position: TimeInterval, expected: NowPlayingSnapshot) {
        guard position.isFinite, let current = track?.snapshot, current.duration > 0,
              current.source == expected.source, current.title == expected.title,
              current.artist == expected.artist else { return }
        command(.seek(min(current.duration, max(0, position))))
    }

    func openSource() {
        guard let source = track?.snapshot.source,
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: source.bundleID).first else { return }
        app.activate(options: [])
    }

    private static let controlsLog = Logger(subsystem: "io.github.cezarprox.brim", category: "controls")

    /// Controls act on the UI first. The overlay flips the icon / freezes or resumes the elapsed
    /// time / starts a skeleton at once, and the command follows through an ordered chain so fast
    /// taps keep their order. Real samples then confirm it, or roll it back after a grace window.
    @discardableResult
    func command(_ command: NowPlayingCommand) -> Task<Void, Never>? {
        guard observed != nil, let displayed = track else {
            Self.controlsLog.notice("\(String(describing: command), privacy: .public) ignored: no track")
            return nil
        }
        Self.controlsLog.notice("\(String(describing: command), privacy: .public) source=\(displayed.snapshot.source.rawValue, privacy: .public)")
        let now = artworkNow()
        let position = displayed.position(at: now)
        let expected = displayed.snapshot
        switch command {
        case .playPause: overlay.togglePlayPause(displayed: expected, position: position, now: now)
        case .next: overlay.startSkip(forward: true, displayed: expected, position: position, now: now)
        case .previous: overlay.startSkip(forward: false, displayed: expected, position: position, now: now)
        case .seek(let target): overlay.startSeek(to: target, displayed: expected, now: now)
        case .setFavorite(let value): overlay.setFavorite(value, now: now)
        case .setShuffle(let value): overlay.setShuffle(value, now: now)
        case .setRepeat(let value): overlay.setRepeat(value, now: now)
        }
        lastCommandIssuedAt = now
        commandError = nil
        status = ""
        render()
        scheduleDeadline()
        let token = actionToken
        let earlier = commandChain
        let task = Task { [weak self] in
            await earlier?.value
            guard let self, token.isValid else { return }
            do {
                try await provider.perform(command, expected: expected, token: token)
                guard token.isValid else { return }
                status = ""
                nudgeRefresh()
            } catch {
                guard token.isValid else { return }
                Self.controlsLog.error("\(String(describing: command), privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                overlay.fail()
                if !(error is CancellationError) {
                    commandError = error.localizedDescription
                    status = error.localizedDescription
                }
                render()
            }
        }
        commandChain = task
        return task
    }

    /// One quick confirmation read after a control, for when no stream event will report it.
    private func nudgeRefresh() {
        guard !streamAlive else { return }
        nudgeTask?.cancel()
        nudgeTask = Task { [weak self] in
            for delay in [0.25, 0.6] as [Double] {
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled, let self, !self.overlay.isEmpty else { return }
                await self.refreshNow()
            }
        }
    }

    /// Wakes once when the oldest pending intent's grace window ends, so an unconfirmed one rolls back.
    private func scheduleDeadline() {
        deadlineTask?.cancel()
        guard let deadline = overlay.nextDeadline else { return }
        let wait = max(0.05, deadline.timeIntervalSince(artworkNow()) + 0.05)
        deadlineTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled, let self else { return }
            self.reconcileNow()
            if let next = self.overlay.nextDeadline, next > self.artworkNow() { self.scheduleDeadline() }
        }
    }

    private func reconcileNow() {
        guard !overlay.isEmpty else { return }
        overlay.reconcile(observed: observed, position: track?.position(at: artworkNow()) ?? 0, now: artworkNow())
        render()
    }

    // MARK: Samples

    /// Takes a real sample (nil = nothing playing), settles pending intents against it and shows the result.
    private func ingest(_ real: NowPlayingSnapshot?, anchor: Date) {
        let now = artworkNow()
        observed = real
        observedAnchor = anchor
        if !overlay.isEmpty {
            overlay.reconcile(observed: real, position: track?.position(at: now) ?? 0, now: now)
            scheduleDeadline()
        }
        render()
    }

    private func render() {
        guard let real = observed else { setTrack(nil); return }
        let display = overlay.apply(to: real, sampleAnchor: observedAnchor, now: artworkNow())
        displayAnchor = display.anchor ?? observedAnchor
        displayTransitioning = display.isTransitioning
        setTrack(display.snapshot)
    }

    func handleStream(_ message: MediaRemoteStreamMessage) {
        switch message {
        case .unavailable:
            streamAlive = false
        case .reply:
            break
        case .none:
            streamAlive = true
            refresh()
        case .nowPlaying(let payload):
            streamAlive = true
            guard let source = MediaRemoteStreamMessage.Payload.source(forBundle: payload.bundle),
                  fixedSources?.contains(source) ?? true else { refresh(); return }
            if !enabledSources.contains(source) { enabledSources.append(source) }
            let snapshot = keepingArtwork(payload.snapshot(source: source, previous: observed))
            let songChanged = observed.map { OptimisticPlayback.key($0) != OptimisticPlayback.key(snapshot) } ?? true
            ingest(snapshot, anchor: payload.timestamp)
            remember(snapshot)
            fillYouTubeAppCover(snapshot)
            // Favorite/shuffle and a cover MediaRemote did not carry come from the app itself.
            if songChanged || (source == .music && snapshot.isFavorite == nil) { refresh() }
        }
    }

    /// Polls (AppleScript, browsers) rarely carry the cover bytes the stream delivered: keep them for the
    /// same song instead of letting the next sample wipe the cover off the island.
    private func keepingArtwork(_ snapshot: NowPlayingSnapshot) -> NowPlayingSnapshot {
        guard snapshot.artworkData == nil, let previous = observed,
              previous.source == snapshot.source, previous.title == snapshot.title,
              previous.artist == snapshot.artist else { return snapshot }
        if previous.artworkData != nil { return snapshot.replacing(artworkData: previous.artworkData) }
        // A cover URL found for this song (the YouTube app's, read from its page) outlives samples without one.
        if snapshot.artworkURL == nil, let url = previous.artworkURL { return snapshot.withArtworkURL(url) }
        return snapshot
    }

    /// MediaRemote names the YouTube app's song correctly but often without a cover, and the app's
    /// accessibility tree can lag a song behind, so the cover is asked of the page by this title.
    private func fillYouTubeAppCover(_ snapshot: NowPlayingSnapshot) {
        guard snapshot.source == .youtubeApp, snapshot.artworkData == nil, snapshot.artworkURL == nil else { return }
        Task { [weak self] in
            guard let url = await YouTubeAppArtwork.url(for: snapshot.title), let self,
                  let current = observed, current.source == snapshot.source, current.title == snapshot.title,
                  current.artist == snapshot.artist, current.artworkData == nil, current.artworkURL == nil else { return }
            ingest(current.withArtworkURL(url), anchor: observedAnchor)
        }
    }

    /// While the stream is live it names the song; a poll of the same song (however the page spells
    /// it) only adds its link, cover URL and playback state instead of replacing the song and its cover.
    private func reconcilingPoll(_ polled: NowPlayingSnapshot) -> NowPlayingSnapshot {
        if streamAlive, let observed, let merged = NowPlayingSongMatch.merge(poll: polled, into: observed) {
            return merged
        }
        return keepingArtwork(polled)
    }

    /// The YouTube app's accessibility tree can name the previous song for a whole track while the
    /// stream has the right one (seen live), so while the stream is live its song wins over a poll of
    /// another song from that app.
    private func isLaggingAppPoll(_ polled: NowPlayingSnapshot) -> Bool {
        guard streamAlive, polled.source == .youtubeApp, let observed, observed.source == .youtubeApp else { return false }
        return NowPlayingSongMatch.merge(poll: polled, into: observed) == nil
    }

    private func setTrack(_ snapshot: NowPlayingSnapshot?) {
        let cap: TimeInterval? = streamAlive ? nil : 3
        if snapshot?.isPlaying == true, isStartingPlayback { isStartingPlayback = false }
        if snapshot?.isPlaying != false {
            pausedAt = nil
        } else if track?.isPlaying == true {
            pausedAt = artworkNow()
        }
        if track?.snapshot.source != snapshot?.source || track?.title != snapshot?.title
            || track?.artist != snapshot?.artist {
            if commandError != nil { commandError = nil }
        }
        guard let snapshot else {
            artworkTask?.cancel()
            artworkKey = nil
            if track != nil { track = nil }
            return
        }
        let key = [snapshot.source.rawValue, snapshot.title, snapshot.artist, snapshot.album,
                   snapshot.artworkURL ?? "", snapshot.albumURL ?? ""].joined(separator: "\u{0}")
        let dataChanged = track?.snapshot.artworkData != snapshot.artworkData
        if key == artworkKey && !dataChanged {
            if track?.snapshot != snapshot || track?.isTransitioning != displayTransitioning
                || (snapshot.isPlaying && track?.sampledAt != displayAnchor) {
                track = NowPlayingTrack(snapshot: snapshot, artwork: track?.artwork, sampledAt: displayAnchor,
                                        stallCap: cap, isTransitioning: displayTransitioning)
            }
            guard track?.artwork == nil, artworkTask == nil, artworkNow() >= artworkRetryAt,
                  snapshot.artworkData != nil || snapshot.artworkURL != nil || snapshot.albumURL != nil else { return }
        }
        // Same song with a new cover source (a URL arriving after the bytes, say): the old cover stays up
        // until the new one decodes, so the island never flashes empty.
        let sameSong = track.map { $0.snapshot.source == snapshot.source && $0.title == snapshot.title
            && $0.artist == snapshot.artist } ?? false
        artworkKey = key
        artworkTask?.cancel()
        track = NowPlayingTrack(snapshot: snapshot, artwork: sameSong ? track?.artwork : nil, sampledAt: displayAnchor,
                                stallCap: cap, isTransitioning: displayTransitioning)
        guard snapshot.artworkData != nil || snapshot.artworkURL != nil || snapshot.albumURL != nil else { return }
        artworkRetryAt = artworkNow().addingTimeInterval(30)
        let loader = artworkLoader
        artworkTask = Task { [weak self] in
            defer {
                if !Task.isCancelled, let self, self.artworkKey == key {
                    self.artworkTask = nil
                    self.artworkRetryAt = self.artworkNow().addingTimeInterval(30)
                }
            }
            // ImageIO decoding must not compete with the notch's layout and animation frames.
            var image: CGImage?
            if let data = snapshot.artworkData {
                image = await Task.detached(priority: .utility) { Self.thumbnail(data) }.value
            }
            guard !Task.isCancelled else { return }
            if image == nil, let data = await loader(snapshot) {
                guard !Task.isCancelled else { return }
                image = await Task.detached(priority: .utility) { Self.thumbnail(data) }.value
            }
            guard !Task.isCancelled, let image,
                  let self, self.artworkKey == key, let current = self.track?.snapshot else { return }
            self.track = NowPlayingTrack(snapshot: current,
                artwork: NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)),
                sampledAt: self.track?.sampledAt ?? Date(), stallCap: self.track?.stallCap,
                isTransitioning: self.track?.isTransitioning ?? false)
        }
    }

    nonisolated private static func thumbnail(_ data: Data) -> CGImage? {
        guard data.count <= 5_000_000,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 640,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        return image
    }
}

// MARK: Filmed demo

extension NowPlayingModel {
    fileprivate struct DemoOriginal {
        let provider: any NowPlayingProviding
        let stream: MediaRemoteStreamClient?
        let resumeStore: NowPlayingResume.Store
        let fixedSources: [NowPlayingSource]?
        let enabledSources: [NowPlayingSource]
    }

    /// Plays `demo`'s sample songs instead of the real players (`--demo` filming). Nothing is saved
    /// meanwhile, and Recently Played is hidden, so no real song shows on screen.
    func enterDemo(provider demo: any NowPlayingProviding) {
        guard demoOriginal == nil else { return }
        stop()
        demoOriginal = DemoOriginal(
            provider: provider, stream: stream, resumeStore: resumeStore, fixedSources: fixedSources,
            enabledSources: enabledSources)
        provider = demo
        stream = nil
        resumeStore = .ephemeral
        fixedSources = [.music]
        enabledSources = [.music]
        clearForDemoSwap()
        start()
    }

    /// Puts the real players and the saved Recently Played back.
    func exitDemo() {
        guard let original = demoOriginal else { return }
        stop()
        demoOriginal = nil
        provider = original.provider
        stream = original.stream
        resumeStore = original.resumeStore
        fixedSources = original.fixedSources
        enabledSources = original.enabledSources
        clearForDemoSwap()
        lastPlayed = resumeStore.load()
        lastArtwork = resumeStore.artwork().flatMap(NSImage.init(data:))
        savedArtwork = lastArtwork
        start()
    }

    private func clearForDemoSwap() {
        track = nil
        observed = nil
        lastPlayed = nil
        lastArtwork = nil
        savedArtwork = nil
        artworkKey = nil
        pausedAt = nil
    }
}
