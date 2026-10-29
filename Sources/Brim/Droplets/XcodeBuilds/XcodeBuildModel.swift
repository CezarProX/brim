import SwiftUI

/// Polls DerivedData while enabled and publishes the build state the island shows.
@MainActor
final class XcodeBuildModel: ObservableObject {
  static let shared = XcodeBuildModel()
  @Published private(set) var status: XcodeBuildStatus = .idle
  /// The newest finished build, kept after the live status clears.
  @Published private(set) var last: XcodeLastBuild?
  /// Whether build watching is on (mirrors the setting, but observable).
  @Published private(set) var watching: Bool
  /// True once DerivedData has been read at least once, so "nothing yet" is not shown prematurely.
  @Published private(set) var scanned = false
  /// DerivedData has a build log for some project.
  @Published private(set) var foundBuildLogs = false
  private var task: Task<Void, Never>?
  private var shownAt: Date?

  /// How long the previous build of the project now building took, for the progress estimate.
  var typicalDuration: TimeInterval? {
    guard let last, last.project == status.project else { return nil }
    return last.duration
  }

  init() { watching = AppSettings.shared.xcodeBuildsEnabled }

  /// Turns watching on from the island itself and starts reading right away.
  func enable() {
    AppSettings.shared.xcodeBuildsEnabled = true
    start()
  }

  func start() {
    guard AppSettings.shared.xcodeBuildsEnabled else { return }
    watching = true
    guard task == nil else { return }
    task = Task { [weak self] in
      while !Task.isCancelled {
        await self?.poll()
        try? await Task.sleep(for: .seconds(self?.pollInterval ?? 1.5))
      }
    }
  }

  func stop() {
    task?.cancel()
    task = nil
    status = .idle
    last = nil
    scanned = false
    foundBuildLogs = false
    watching = AppSettings.shared.xcodeBuildsEnabled
  }

  /// Applies a reading; separated from the timer so tests and previews can drive it.
  func apply(_ snapshot: XcodeLogSnapshot, now: Date = .now) {
    scanned = true
    foundBuildLogs = true
    let newest = XcodeBuildDetector.lastBuild(snapshot)
    if newest != last { last = newest }
    let next = XcodeBuildDetector.status(snapshot, previous: status, now: now)
    guard next != status else { return expire(now) }
    let wasBuilding = status.isBuilding
    status = next
    shownAt = now
    if wasBuilding { announce(next) }
  }

  /// Shows a status directly, for previews and render tests.
  func preview(_ next: XcodeBuildStatus, last: XcodeLastBuild? = nil, watching: Bool = true, found: Bool = true) {
    status = next
    self.last = last
    self.watching = watching
    scanned = true
    foundBuildLogs = found
  }

  private func expire(_ now: Date) {
    switch status {
    case .succeeded, .failed:
      if let shownAt, now.timeIntervalSince(shownAt) > XcodeBuildDetector.resultWindow { status = .idle }
    default: break
    }
  }

  /// Quick while Xcode is open or a build runs; otherwise only often enough to catch a
  /// command-line build starting, without spawning `pgrep` and walking DerivedData every 1.5 s.
  private var pollInterval: TimeInterval {
    if status.isBuilding { return 1.5 }
    let xcodeOpen = NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "com.apple.dt.Xcode" }
    return xcodeOpen ? 1.5 : 6
  }

  private func poll() async {
    let running = await XcodeLogScanner.isXcodebuildRunning()
    let snapshot = await Task.detached(priority: .utility) { XcodeLogScanner.snapshot(xcodebuildRunning: running) }.value
    if let snapshot { apply(snapshot) } else {
      scanned = true
      foundBuildLogs = false
      expire(.now)
    }
  }

  private func announce(_ result: XcodeBuildStatus) {
    let flashes = IslandFlashCenter.shared
    switch result {
    case .succeeded(let project, let duration, let warnings):
      flashes.show(
        "Build succeeded", symbol: "checkmark.circle.fill", tint: .green,
        detail: [project, duration.map(XcodeBuildDetector.clock), warnings > 0 ? "\(warnings) warnings" : nil].compactMap { $0 }.joined(separator: " · "))
    case .failed(let project, let duration, let errors):
      flashes.show(
        "Build failed", symbol: "xmark.octagon.fill", tint: .red,
        detail: [project, duration.map(XcodeBuildDetector.clock), "\(errors) error\(errors == 1 ? "" : "s")"].compactMap { $0 }.joined(separator: " · "))
    default: break
    }
  }
}
