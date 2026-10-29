import AppKit
import Combine

/// Playlists for Apple Music's "Add to Playlist" button. Listing happens off the main thread and
/// is cached briefly; adding duplicates the current track into the chosen playlist.
@MainActor
final class MusicPlaylistsModel: ObservableObject {
  static let shared = MusicPlaylistsModel()

  enum Outcome: Equatable { case none, added(String), failed(String) }

  @Published private(set) var playlists: [String] = []
  @Published private(set) var isLoading = false
  @Published private(set) var outcome: Outcome = .none
  private var loadedAt: Date?
  private var dismissTask: Task<Void, Never>?
  nonisolated static let cacheLifetime: TimeInterval = 60

  /// Pure rule: reload when never loaded or the cache is stale.
  nonisolated static func needsRefresh(loadedAt: Date?, now: Date) -> Bool {
    guard let loadedAt else { return true }
    return now.timeIntervalSince(loadedAt) >= cacheLifetime
  }

  func refresh(force: Bool = false) {
    guard !isLoading, force || Self.needsRefresh(loadedAt: loadedAt, now: Date()) else { return }
    isLoading = true
    Task {
      let result = await Self.run(MusicPlaylistScripts.listPlaylists)
      isLoading = false
      switch result {
      case .success(let descriptor):
        let count = descriptor.numberOfItems
        let names = count > 0 ? (1...count).compactMap { descriptor.atIndex($0)?.stringValue } : []
        playlists = MusicPlaylistScripts.cleaned(names)
        loadedAt = Date()
      case .notRunning: break  // nothing to list; never launch Music just to fill a menu
      case .failure(let message): outcome = .failed(message); scheduleDismiss()
      }
    }
  }

  func add(to playlist: String) {
    Task {
      switch await Self.run(MusicPlaylistScripts.addCurrentTrack(to: playlist)) {
      case .success: outcome = .added(playlist)
      case .notRunning: outcome = .failed("Open Music and play the song first.")
      case .failure(let message): outcome = .failed(message)
      }
      scheduleDismiss()
    }
  }

  private func scheduleDismiss() {
    dismissTask?.cancel()
    dismissTask = Task { [weak self] in
      try? await Task.sleep(for: .seconds(2.5))
      if !Task.isCancelled { self?.outcome = .none }
    }
  }

  private enum RunResult { case success(NSAppleEventDescriptor), failure(String), notRunning }

  /// Apple Events to a closed app would launch it, and tests must never drive the user's Music.
  nonisolated static var canRun: Bool {
    let underTest = NSClassFromString("XCTestCase") != nil || ProcessInfo.processInfo.processName.contains("xctest")
      || ProcessInfo.processInfo.processName.contains("swiftpm-testing")
      || CommandLine.arguments.contains { $0.hasSuffix(".xctest") }
    guard !underTest else { return false }
    return NSRunningApplication.runningApplications(withBundleIdentifier: NowPlayingSource.music.bundleID)
      .contains { !$0.isTerminated }
  }

  private static func run(_ source: String) async -> RunResult {
    guard canRun else { return .notRunning }
    return await Task.detached(priority: .userInitiated) {
      var info: NSDictionary?
      guard let script = NSAppleScript(source: source) else { return .failure("Could not prepare the request.") }
      let descriptor = script.executeAndReturnError(&info)
      if let info {
        let number = info[NSAppleScript.errorNumber] as? Int ?? 0
        if number == -1743 { return .failure("Allow Brim to control Music in Automation settings.") }
        return .failure("Music could not add this track (is it in your library?).")
      }
      return .success(descriptor)
    }.value
  }
}
