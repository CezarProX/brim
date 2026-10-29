import Foundation

/// Visual style of the compact-island music bars.
enum VisualizerStyle: String, CaseIterable, Identifiable {
  case regular, gradient
  var id: String { rawValue }
  var title: String { self == .regular ? "Regular" : "Gradient" }
}

/// Extra buttons around the transport controls ("Apple Music Controls").
enum MediaButtonKind: String, CaseIterable, Identifiable {
  case none, shuffle, `repeat`, favorite, addToPlaylist, output, lyrics
  var id: String { rawValue }
  var title: String {
    switch self {
    case .none: return "None"
    case .shuffle: return "Shuffle"
    case .repeat: return "Repeat"
    case .favorite: return "Favorite"
    case .addToPlaylist: return "Add to Playlist"
    case .output: return "Output"
    case .lyrics: return "Lyrics"
    }
  }
}

extension AppSettings {
  private enum MediaKey {
    static let lyricsEnabled = "mediaLyricsEnabled"
    static let lyricsAutoExpand = "mediaLyricsAutoExpand"
    static let trackSwipe = "mediaTrackSwipeEnabled"
    static let reverseSwipe = "mediaReverseSwipe"
    static let liveVisualizer = "mediaLiveVisualizer"
    static let visualizerStyle = "mediaVisualizerStyle"
    static let scrollLongNames = "mediaScrollLongNames"
    static let keepSongVisible = "mediaKeepSongNameVisible"
    static let keepArtistVisible = "mediaKeepArtistVisible"
    static let notchTrackTitle = "mediaNotchTrackTitle"
    static let hideInFullscreen = "mediaHideInFullscreen"
    static let leftButtons = "mediaLeftButtons"
    static let rightButtons = "mediaRightButtons"
    static let defaultMusicApp = "mediaDefaultMusicApp"
    static let motionArtwork = "mediaMotionArtwork"
    static let floatingLyrics = "mediaFloatingLyrics"
  }

  private func mediaBool(_ key: String, _ fallback: Bool) -> Bool {
    defaults.object(forKey: key) as? Bool ?? fallback
  }

  /// Timed lyrics come from lrclib.net, so they stay off until the user opts in.
  var lyricsEnabled: Bool {
    get { mediaBool(MediaKey.lyricsEnabled, false) }
    set { defaults.set(newValue, forKey: MediaKey.lyricsEnabled) }
  }
  var lyricsAutoExpand: Bool {
    get { mediaBool(MediaKey.lyricsAutoExpand, false) }
    set { defaults.set(newValue, forKey: MediaKey.lyricsAutoExpand) }
  }
  var trackSwipeEnabled: Bool {
    get { mediaBool(MediaKey.trackSwipe, true) }
    set { defaults.set(newValue, forKey: MediaKey.trackSwipe) }
  }
  var reverseSwipeDirection: Bool {
    get { mediaBool(MediaKey.reverseSwipe, false) }
    set { defaults.set(newValue, forKey: MediaKey.reverseSwipe) }
  }
  /// Needs the system-audio capture permission, so it is opt-in.
  var liveVisualizerEnabled: Bool {
    get { mediaBool(MediaKey.liveVisualizer, false) }
    set { defaults.set(newValue, forKey: MediaKey.liveVisualizer) }
  }
  var visualizerStyle: VisualizerStyle {
    get { VisualizerStyle(rawValue: defaults.string(forKey: MediaKey.visualizerStyle) ?? "") ?? .regular }
    set { defaults.set(newValue.rawValue, forKey: MediaKey.visualizerStyle) }
  }
  var scrollLongNames: Bool {
    get { mediaBool(MediaKey.scrollLongNames, true) }
    set { defaults.set(newValue, forKey: MediaKey.scrollLongNames) }
  }
  var keepSongNameVisible: Bool {
    get { mediaBool(MediaKey.keepSongVisible, false) }
    set { defaults.set(newValue, forKey: MediaKey.keepSongVisible) }
  }
  var keepArtistVisible: Bool {
    get { mediaBool(MediaKey.keepArtistVisible, false) }
    set { defaults.set(newValue, forKey: MediaKey.keepArtistVisible) }
  }
  var notchTrackTitle: Bool {
    get { mediaBool(MediaKey.notchTrackTitle, true) }
    set { defaults.set(newValue, forKey: MediaKey.notchTrackTitle) }
  }
  var hideMediaInFullscreen: Bool {
    get { mediaBool(MediaKey.hideInFullscreen, false) }
    set { defaults.set(newValue, forKey: MediaKey.hideInFullscreen) }
  }
  /// Extra buttons left/right of the transport row (at most two per side).
  var mediaLeftButtons: [MediaButtonKind] {
    get { mediaButtons(MediaKey.leftButtons, fallback: [.favorite]) }
    set { defaults.set(newValue.prefix(2).map(\.rawValue), forKey: MediaKey.leftButtons) }
  }
  var mediaRightButtons: [MediaButtonKind] {
    get { mediaButtons(MediaKey.rightButtons, fallback: [.output]) }
    set { defaults.set(newValue.prefix(2).map(\.rawValue), forKey: MediaKey.rightButtons) }
  }
  /// Slow zoom/pan on the cover while music plays. Apple's animated covers are not available,
  /// so this animates the static artwork instead. On by default; Reduce Motion always wins.
  var mediaMotionArtwork: Bool {
    get { mediaBool(MediaKey.motionArtwork, true) }
    set { defaults.set(newValue, forKey: MediaKey.motionArtwork) }
  }
  /// Liquid Player: lyrics float over the whole window instead of sitting in a box.
  var mediaFloatingLyrics: Bool {
    get { mediaBool(MediaKey.floatingLyrics, false) }
    set { defaults.set(newValue, forKey: MediaKey.floatingLyrics) }
  }
  /// Bundle id of the player to open when nothing is playing; empty means automatic.
  var defaultMusicApp: String {
    get { defaults.string(forKey: MediaKey.defaultMusicApp) ?? "" }
    set { defaults.set(newValue, forKey: MediaKey.defaultMusicApp) }
  }

  private func mediaButtons(_ key: String, fallback: [MediaButtonKind]) -> [MediaButtonKind] {
    guard let raw = defaults.stringArray(forKey: key) else { return fallback }
    return Array(raw.compactMap(MediaButtonKind.init(rawValue:)).filter { $0 != .none }.prefix(2))
  }
}
