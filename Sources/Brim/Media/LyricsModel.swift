import Combine
import Foundation

/// Lyrics for the track on the island: cache first, then LRCLIB, off the main thread.
@MainActor
final class LyricsModel: ObservableObject {
  static let shared = LyricsModel()

  enum State: Equatable {
    case off, loading, ready(TimedLyrics), none
    var lyrics: TimedLyrics? { if case .ready(let lyrics) = self { return lyrics } else { return nil } }
  }

  @Published private(set) var state: State = .off
  private let store: LyricsStore
  private let provider: LyricsProvider
  private var currentKey: String?
  private var task: Task<Void, Never>?
  /// Waits before asking again when LRCLIB could not be reached (it often answers "busy").
  private let retryDelays: [TimeInterval]

  init(store: LyricsStore = .standard, provider: LyricsProvider = .live, state: State = .off,
       retryDelays: [TimeInterval] = [3, 10, 30]) {
    self.store = store
    self.provider = provider
    self.state = state
    self.retryDelays = retryDelays
  }

  func sync(track: NowPlayingTrack?, enabled: Bool) {
    guard enabled, let track, !track.title.isEmpty else {
      task?.cancel()
      currentKey = nil
      if state != .off { state = .off }
      return
    }
    let query = LyricsProvider.Query(title: track.title, artist: track.artist,
                                     album: track.album, duration: track.duration)
    let key = LyricsStore.key(title: query.title, artist: query.artist, album: query.album,
                              duration: query.duration)
    guard key != currentKey else { return }
    currentKey = key
    task?.cancel()
    state = .loading
    let store = store, provider = provider, retryDelays = retryDelays
    task = Task { [weak self] in
      let text: String?
      if let cached = store.load(key: key) { text = cached.synced }
      else {
        var outcome = await provider.lookup(query)
        for delay in retryDelays where outcome == .failed {
          try? await Task.sleep(for: .seconds(delay))
          if Task.isCancelled { return }
          outcome = await provider.lookup(query)
        }
        if Task.isCancelled { return }
        switch outcome {
        case .found(let fetched):
          store.save(.init(synced: fetched, fetchedAt: .now), key: key)
          text = fetched
        case .missing:
          store.save(.init(synced: nil, fetchedAt: .now), key: key)
          text = nil
        case .failed:
          // Unreachable is not "no lyrics": nothing is cached, so the next play asks again.
          text = nil
        }
      }
      let parsed = text.map(LRCParser.parse)
      guard let self, !Task.isCancelled, self.currentKey == key else { return }
      self.state = parsed?.isSynced == true ? .ready(parsed!) : .none
    }
  }
}
