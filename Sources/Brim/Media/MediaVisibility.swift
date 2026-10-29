import Combine
import Foundation

/// Decides whether the current track may appear in the island: the source allow-list and private-window
/// hiding. Browser inspection is slow, so it runs off the main thread and the answer is cached; the
/// synchronous `allows` never blocks. When the cached answer changes, the Now Playing model is nudged
/// so views that call `isInIsland()` re-evaluate.
@MainActor
final class MediaVisibility {
  static let shared = MediaVisibility()
  private var privateKey: String?
  private var checking = false
  private var timer: Timer?
  private let probe: @Sendable (String) -> [BrowserWindowInfo]
  private let settings: AppSettings

  init(settings: AppSettings = .shared, probe: @escaping @Sendable (String) -> [BrowserWindowInfo] = { BrowserWindowProbe.windows(bundleID: $0) }) {
    self.settings = settings
    self.probe = probe
  }

  func allows(_ track: NowPlayingTrack) -> Bool {
    let snapshot = track.snapshot
    guard MediaVisibilityRules.isSourceAllowed(bundleID: snapshot.source.bundleID, allowed: settings.mediaAllowedSources) else { return false }
    if settings.mediaHidePrivateBrowsing, snapshot.source.isBrowser, privateKey == Self.key(snapshot) { return false }
    return true
  }

  /// Call on every track change (MediaServices does). Starts a light re-check while a browser plays.
  func update(track: NowPlayingTrack?) {
    guard settings.mediaHidePrivateBrowsing, let snapshot = track?.snapshot, snapshot.source.isBrowser else {
      timer?.invalidate(); timer = nil
      if privateKey != nil { privateKey = nil; NowPlayingModel.shared.objectWillChange.send() }
      return
    }
    if timer == nil {
      timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
        Task { @MainActor in self?.update(track: NowPlayingModel.shared.track) }
      }
    }
    check(snapshot)
  }

  private func check(_ snapshot: NowPlayingSnapshot) {
    guard !checking else { return }
    checking = true
    let bundle = snapshot.source.bundleID, title = snapshot.title, key = Self.key(snapshot)
    let probe = self.probe
    Task.detached(priority: .utility) { [weak self] in
      let isPrivate = MediaVisibilityRules.isPrivateMedia(trackTitle: title, windows: probe(bundle))
      await self?.finishCheck(isPrivate: isPrivate, key: key)
    }
  }

  private func finishCheck(isPrivate: Bool, key: String) {
    checking = false
    let next: String? = isPrivate ? key : nil
    guard privateKey != next else { return }
    privateKey = next
    NowPlayingModel.shared.objectWillChange.send()
  }

  private static func key(_ s: NowPlayingSnapshot) -> String { "\(s.source.rawValue)|\(s.title)" }
}
