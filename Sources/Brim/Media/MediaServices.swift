import Combine
import Foundation

/// One switchboard the integrator starts: it feeds the live visualizer and the lyrics
/// model from the shared Now Playing model and reacts to setting changes.
@MainActor
final class MediaServices {
  static let shared = MediaServices()
  private var cancellables: Set<AnyCancellable> = []
  private var started = false

  func start(nowPlaying: NowPlayingModel? = nil) {
    guard !started else { return }
    let nowPlaying = nowPlaying ?? .shared
    started = true
    nowPlaying.$track
      .sink { [weak self] _ in self?.sync(nowPlaying) }
      .store(in: &cancellables)
    NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
      .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
      .sink { [weak self] _ in self?.sync(nowPlaying) }
      .store(in: &cancellables)
    sync(nowPlaying)
  }

  func stop() {
    cancellables.removeAll()
    started = false
    LiveAudioMonitor.shared.stop()
  }

  /// Settings changes call this too (the Media section does after toggling).
  func sync(_ model: NowPlayingModel? = nil) {
    let nowPlaying = model ?? .shared
    let settings = AppSettings.shared
    let track = nowPlaying.track
    LiveAudioMonitor.shared.update(
      bundleID: track?.snapshot.source.bundleID, isPlaying: track?.isPlaying == true,
      enabled: settings.liveVisualizerEnabled)
    LyricsModel.shared.sync(track: track, enabled: settings.lyricsEnabled)
    PlayingNextModel.shared.trackChanged(track)
    MediaVisibility.shared.update(track: track)
    AudioQualityModel.shared.sync(track: track)
    DiscordPresence.shared.sync(track: track, settings: settings)
  }
}
