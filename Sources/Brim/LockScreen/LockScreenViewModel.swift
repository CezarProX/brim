import Combine
import Foundation

/// Gathers what the lock-screen cards show from the app's existing models, and routes the card
/// buttons back to them. Nothing here is lock-screen specific data; it only reads.
@MainActor
final class LockScreenViewModel: ObservableObject {
    @Published private(set) var content = LockCardsContent()
    @Published private(set) var statusItems: [LockStatusItem] = []
    /// True while the fullscreen artwork scene is showing.
    @Published var artworkSceneOpen = false
    /// Bumped when a lock-screen setting changes, so SwiftUI hosts redraw immediately.
    @Published private(set) var settingsRevision = 0
    func settingsDidChange() { settingsRevision += 1; refresh() }

    /// Lyrics row is wanted: setting on, the island's lyrics fetch on, and synced lyrics ready.
    var showsLyrics: Bool {
        settings.lockScreenLyrics && settings.lyricsEnabled && settings.lockScreenMediaCard
            && content.media != nil && LyricsModel.shared.state.lyrics != nil
    }

    private let settings: AppSettings
    private let nowPlaying: NowPlayingModel
    private let focus: FocusTimerModel
    private let nativeTimer: NativeTimerModel
    private let keepAwake: KeepAwakeModel
    private let registry: LockStatusRegistry

    init(settings: AppSettings = .shared, nowPlaying: NowPlayingModel? = nil,
         focus: FocusTimerModel? = nil, nativeTimer: NativeTimerModel? = nil,
         keepAwake: KeepAwakeModel? = nil, registry: LockStatusRegistry? = nil) {
        self.settings = settings
        self.nowPlaying = nowPlaying ?? .shared
        self.focus = focus ?? .shared
        self.nativeTimer = nativeTimer ?? .shared
        self.keepAwake = keepAwake ?? .shared
        self.registry = registry ?? .shared
    }

    var inputs: LockCardInputs {
        LockCardInputs(
            mediaEnabled: settings.lockScreenMediaCard, timerEnabled: settings.lockScreenTimerCard,
            awakeEnabled: settings.lockScreenAwakeCard,
            hasMedia: content.media != nil, timerActive: content.timer != nil, awakeActive: content.awake != nil,
            statusRowEnabled: settings.lockScreenStatusRow, statusItemCount: statusItems.count)
    }

    var look: LockScreenLook { settings.lockScreenLook }

    func refresh(now: Date = .now) {
        var next = LockCardsContent()
        if let track = nowPlaying.track,
           LockMediaVisibility.shouldShow(
               hasTrack: true, isPlaying: track.isPlaying,
               pausedFor: nowPlaying.pausedAt.map { now.timeIntervalSince($0) },
               hideAfterMinutes: settings.lockScreenHideAfterPausedMinutes) {
            next.media = LockMediaInfo(track: track)
        }
        next.timer = currentTimer()
        if keepAwake.isActive { next.awake = LockAwakeInfo(until: keepAwake.until) }
        content = next
        let hidden = settings.lockScreenHiddenStatusItems
        statusItems = registry.items(now: now).filter { !hidden.contains($0.id) }
    }

    private func currentTimer() -> LockTimerInfo? {
        if focus.isActive && !focus.completed {
            let resting = focus.isPomodoro && focus.phase == .rest
            return LockTimerInfo(
                title: focus.isPomodoro ? (resting ? "Break" : "Focus") : "Timer",
                symbol: resting ? "cup.and.saucer.fill" : (focus.isPomodoro ? "brain.head.profile" : "timer"),
                tint: resting ? .green : .orange, duration: focus.duration,
                endDate: focus.deadline, pausedRemaining: focus.pausedRemaining)
        }
        if let native = nativeTimer.activeTimer {
            return LockTimerInfo(
                title: native.title.isEmpty ? "Timer" : native.title, symbol: "timer", tint: .orange,
                duration: native.duration, endDate: native.endDate,
                pausedRemaining: native.pausedRemaining,
                canControl: nativeTimer.controlCapability != .accessibilityPermissionRequired)
        }
        return nil
    }

    // MARK: Actions (the same command path the island uses)

    var actions: LockCardActions {
        LockCardActions(
            previous: { [weak self] in self?.nowPlaying.previous() },
            playPause: { [weak self] in self?.nowPlaying.playPause() },
            next: { [weak self] in self?.nowPlaying.next() },
            toggleTimer: { [weak self] in self?.toggleTimer() },
            stopAwake: { [weak self] in self?.keepAwake.stop() },
            openArtwork: settings.lockScreenArtworkScene ? { [weak self] in self?.artworkSceneOpen = true } : nil,
            seek: { [weak self] position in
                guard let self, let snapshot = self.nowPlaying.track?.snapshot else { return }
                self.nowPlaying.seek(to: position, expected: snapshot)
            })
    }

    private func toggleTimer() {
        if focus.isActive && !focus.completed {
            focus.isPaused ? focus.resume() : focus.pause()
        } else if let native = nativeTimer.activeTimer {
            let model = nativeTimer
            Task { @MainActor in
                if native.isPaused { await model.resume(expectedID: native.id) }
                else { await model.pause(expectedID: native.id) }
            }
        }
    }
}
