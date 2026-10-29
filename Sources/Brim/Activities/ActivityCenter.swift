import AppKit
import Combine

/// Shared data sources, independent of the shape and per-display presentation.
@MainActor
final class ActivityCenter: ObservableObject {
  static let shared = ActivityCenter()
  let calendar: CalendarActivityModel
  let batteries = DeviceBatteryModel.shared
  let focus = FocusTimerModel.shared
  let workspace = WorkspaceActivityModel.shared
  let sharing = SharingActivityModel.shared
  let dictation = DictationModel.shared
  let agent = AgentActivityModel.shared
  let flashes = IslandFlashCenter.shared
  let recorder = VoiceRecorderModel.shared
  let keepAwake = KeepAwakeModel.shared
  let browser = BrowserSkinModel.shared
  let coding = CodingAgentModel.shared
  let signals = SystemSignalsMonitor.shared
  let downloads: DownloadProgressModel
  let builds = XcodeBuildModel.shared
  let indicators = SystemStatusIndicators.shared
  private var subscriptions = Set<AnyCancellable>()

  /// The first-run tour passes its own calendar and downloads, filled with samples.
  init(calendar: CalendarActivityModel = .shared, downloads: DownloadProgressModel = .shared) {
    self.calendar = calendar
    self.downloads = downloads
    let changes = [
      calendar.objectWillChange, batteries.objectWillChange, focus.objectWillChange,
      workspace.objectWillChange, sharing.objectWillChange, dictation.objectWillChange,
      agent.objectWillChange, flashes.objectWillChange, recorder.objectWillChange,
      keepAwake.objectWillChange, browser.objectWillChange, coding.objectWillChange,
      signals.objectWillChange, downloads.objectWillChange, builds.objectWillChange,
      indicators.objectWillChange,
    ]
    for change in changes {
      change.sink { [weak self] _ in
        Task { @MainActor in self?.objectWillChange.send() }
      }.store(in: &subscriptions)
    }
  }

  func start() {
    calendar.start()
    batteries.start()
    workspace.start()
    agent.start()
    browser.start()
    coding.start()
  }
  func stop() {
    calendar.stop()
    batteries.stop()
    workspace.stop()
    focus.stop()
    dictation.stop()
    agent.stop()
    browser.stop()
    coding.stop()
    if recorder.isRecording { recorder.stopRecording() }
  }

  /// Which of camera and microphone is in use right now.
  var privacy: PrivacyIndicator? { PrivacyIndicator(camera: signals.cameraInUse, microphone: signals.microphoneInUse) }

  var activeKinds: [IslandActivity] {
    var kinds: [IslandActivity] = []
    if dictation.isRecording { kinds.append(.dictation) }
    if focus.isActive { kinds.append(.focus) }
    if calendar.isLive { kinds.append(.calendar) }
    if sharing.isActive { kinds.append(.transfer) }
    if agent.active != nil || coding.session?.isLive() == true { kinds.append(.agent) }
    if recorder.isRecording { kinds.append(.recorder) }
    if keepAwake.isActive { kinds.append(.keepAwake) }
    // Shown while a supported browser is in front, including to ask for access.
    if browser.snapshot != nil || (browser.frontBrowser != nil && browser.needsPermission) {
      kinds.append(.browser)
    }
    if downloads.active != nil { kinds.append(.download) }
    if builds.status != .idle { kinds.append(.build) }
    let settings = AppSettings.shared
    if settings.hudPrivacyIndicator, privacy != nil { kinds.append(.privacy) }
    if settings.hudFocus, indicators.focusOn { kinds.append(.dnd) }
    if settings.hudHotspot, indicators.hotspot { kinds.append(.hotspot) }
    if batteries.announcementUntil > .now { kinds.append(.devices) }
    if flashes.current != nil { kinds.append(.system) }
    if AppSettings.shared.workspaceActivityEnabled, !workspace.appName.isEmpty {
      kinds.append(.workspace)
    }
    return kinds
  }

  func compactValue(_ activity: IslandActivity) -> String {
    switch activity {
    case .focus:
      return focus.completed ? "Done" : CompactTimerReadout.format(focus.remaining(), minimal: true)
    case .calendar:
      guard let meeting = calendar.meeting else { return "" }
      let minutes = Int(ceil(meeting.startsAt.timeIntervalSinceNow / 60))
      return minutes <= 0 ? "Now" : "\(minutes)m"
    case .devices:
      if let announced = batteries.announced { return "\(announced.lowest)%" }
      return batteries.devices.first.map { "\($0.percent)%" } ?? ""
    case .dictation: return DictationCompactLine.tail(dictation.transcript)
    case .transfer: return "\(sharing.files.count)"
    case .system: return flashes.current?.title ?? ""
    case .workspace: return String(workspace.appName.prefix(8))
    case .agent:
      if let session = coding.session, session.isLive() { return session.statusText }
      return agent.active?.state.rawValue.capitalized ?? ""
    case .recorder:
      guard let started = recorder.recordingStarted else { return "" }
      return CompactTimerReadout.format(Date.now.timeIntervalSince(started))
    case .keepAwake:
      guard let until = keepAwake.until else { return "On" }
      return CompactTimerReadout.format(until.timeIntervalSinceNow, minimal: true)
    case .browser: return browser.snapshot.map { "\($0.tabCount)" } ?? "Allow"
    case .download: return downloads.active?.trailingText ?? ""
    case .privacy, .dnd: return "On"
    case .hotspot: return "Active"
    default: return ""
    }
  }

  /// "17.8k" style token counts for the compact island.
  static func tokens(_ count: Int) -> String {
    count >= 1000 ? String(format: "%.1fk", Double(count) / 1000) : "\(count)"
  }
}
