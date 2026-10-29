import Foundation

@MainActor
final class FocusTimerModel: ObservableObject {
  enum Phase: Equatable { case focus, rest }

  static let shared = FocusTimerModel(
    flashes: .shared, autoStartNext: { AppSettings.shared.pomodoroAutoStart },
    hooks: .live)
  /// The dial picks up to ten hours.
  static let maximumMinutes = 600
  @Published private(set) var deadline: Date?
  @Published private(set) var pausedRemaining: TimeInterval?
  @Published private(set) var duration: TimeInterval = 25 * 60
  @Published private(set) var completed = false
  @Published private(set) var phase: Phase = .focus
  @Published private(set) var isPomodoro = false
  @Published private(set) var completedSessions = 0
  private var focusLength: TimeInterval = 25 * 60
  private var restLength: TimeInterval = 5 * 60
  private var ticker: Timer?
  /// Where phase changes are announced; only the app-wide timer announces.
  private let flashes: IslandFlashCenter?
  /// Whether the next Pomodoro phase starts by itself; off waits, paused, for Play.
  private let autoStartNext: () -> Bool
  /// Side effects of a Pomodoro: counting sessions, the end chime, ambient noise.
  struct Hooks {
    var sessionCompleted: @MainActor (Date) -> Void = { _ in }
    var phaseEnded: @MainActor () -> Void = {}
    var ambient: @MainActor (Bool) -> Void = { _ in }

    @MainActor static var live: Hooks {
      Hooks(
        sessionCompleted: { FocusSessionStore.shared.recordSession(at: $0) },
        phaseEnded: { PomodoroEndSound.current.play() },
        ambient: { AmbientSoundPlayer.shared.play($0 ? AmbientSound.current : .off) })
    }
  }
  private let hooks: Hooks
  var isActive: Bool { deadline != nil || pausedRemaining != nil || completed }
  var isPaused: Bool { pausedRemaining != nil }

  init(
    flashes: IslandFlashCenter? = nil, autoStartNext: @escaping () -> Bool = { true },
    hooks: Hooks = Hooks()
  ) {
    self.flashes = flashes
    self.autoStartNext = autoStartNext
    self.hooks = hooks
  }

  /// Ambient noise plays only while a focus phase is actually counting down.
  private func syncAmbient() {
    hooks.ambient(isPomodoro && phase == .focus && deadline != nil)
  }

  func remaining(at now: Date = .now) -> TimeInterval {
    pausedRemaining ?? max(0, deadline?.timeIntervalSince(now) ?? 0)
  }

  func start(minutes: Int, now: Date = .now) {
    isPomodoro = false
    phase = .focus
    completedSessions = 0
    begin(TimeInterval(min(Self.maximumMinutes, max(1, minutes)) * 60), now: now)
  }

  /// Alternates focus and rest intervals until stopped.
  func startPomodoro(focusMinutes: Int = 25, breakMinutes: Int = 5, now: Date = .now) {
    focusLength = TimeInterval(min(PomodoroTapeMath.range.upperBound, max(1, focusMinutes)) * 60)
    restLength = TimeInterval(min(60, max(1, breakMinutes)) * 60)
    isPomodoro = true
    phase = .focus
    completedSessions = 0
    begin(focusLength, now: now)
  }

  private func begin(_ length: TimeInterval, now: Date) {
    duration = length
    pausedRemaining = nil
    completed = false
    deadline = now.addingTimeInterval(length)
    startTicker()
    syncAmbient()
  }

  private func startTicker() {
    ticker?.invalidate()
    ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.tick() }
    }
  }

  func pause(now: Date = .now) {
    guard deadline != nil else { return }
    let seconds = remaining(at: now)
    if seconds <= 0 {
      tick(now: now)
      return
    }
    pausedRemaining = seconds
    deadline = nil
    ticker?.invalidate()
    ticker = nil
    syncAmbient()
  }

  func resume(now: Date = .now) {
    guard let pausedRemaining else { return }
    deadline = now.addingTimeInterval(pausedRemaining)
    self.pausedRemaining = nil
    startTicker()
    syncAmbient()
  }

  func tick(now: Date = .now) {
    guard let deadline, deadline <= now else { return }
    if isPomodoro {
      if phase == .focus {
        completedSessions += 1
        hooks.sessionCompleted(deadline)
      }
      hooks.phaseEnded()
      phase = phase == .focus ? .rest : .focus
      begin(phase == .focus ? focusLength : restLength, now: deadline)
      if !autoStartNext() { holdForPlay() }
      flashes?.show(
        phase == .rest ? "Break time" : "Back to focus", symbol: phase == .rest ? "cup.and.saucer.fill" : "hourglass",
        tint: .orange)
      return
    }
    self.deadline = nil
    completed = true
    ticker?.invalidate()
    ticker = nil
    hooks.phaseEnded()
    flashes?.show("Timer done", symbol: "checkmark.circle.fill", tint: .orange)
  }

  /// Leaves the freshly begun phase paused at its full length until the user presses Play.
  private func holdForPlay() {
    pausedRemaining = duration
    deadline = nil
    ticker?.invalidate()
    ticker = nil
    syncAmbient()
  }

  func stop() {
    ticker?.invalidate()
    ticker = nil
    deadline = nil
    pausedRemaining = nil
    completed = false
    isPomodoro = false
    phase = .focus
    completedSessions = 0
    syncAmbient()
  }
}
