import CoreGraphics

/// Which extra buttons are shown beside the transport row, and where (600-point space).
enum MediaButtonSlots {
  struct Capabilities: Equatable {
    var hasFavorite: Bool
    var hasShuffle: Bool
    var lyricsEnabled: Bool
    /// The player reports a repeat state (Apple Music, Spotify).
    var hasRepeat = false
    /// Apple Music only: the current track can be added to a user playlist.
    var hasPlaylist = false

    init(hasFavorite: Bool, hasShuffle: Bool, lyricsEnabled: Bool, hasRepeat: Bool = false, hasPlaylist: Bool = false) {
      self.hasFavorite = hasFavorite
      self.hasShuffle = hasShuffle
      self.lyricsEnabled = lyricsEnabled
      self.hasRepeat = hasRepeat
      self.hasPlaylist = hasPlaylist
    }

    /// What a source can honestly offer. Spotify's scripting has no like/save, so Favorite
    /// and Add to Playlist are Apple Music only; YouTube Music exposes neither repeat nor shuffle.
    init(snapshot: NowPlayingSnapshot, lyricsEnabled: Bool) {
      self.init(hasFavorite: snapshot.isFavorite != nil, hasShuffle: snapshot.isShuffling != nil,
                lyricsEnabled: lyricsEnabled, hasRepeat: snapshot.repeatMode != nil,
                hasPlaylist: snapshot.source == .music)
    }
  }

  /// Drops buttons the current player cannot honour. A Favorite slot on a
  /// player without favorites falls back to Shuffle (Spotify), as the single side button did.
  static func resolve(_ kinds: [MediaButtonKind], capabilities: Capabilities) -> [MediaButtonKind] {
    var result: [MediaButtonKind] = []
    for kind in kinds {
      var resolved: MediaButtonKind? = kind
      if kind == .favorite, !capabilities.hasFavorite { resolved = capabilities.hasShuffle ? .shuffle : nil }
      if resolved == .shuffle, !capabilities.hasShuffle { resolved = nil }
      if resolved == .favorite, !capabilities.hasFavorite { resolved = nil }
      if resolved == .lyrics, !capabilities.lyricsEnabled { resolved = nil }
      if resolved == .repeat, !capabilities.hasRepeat { resolved = nil }
      if resolved == .addToPlaylist, !capabilities.hasPlaylist { resolved = nil }
      if resolved == MediaButtonKind.none { resolved = nil }
      if let resolved, !result.contains(resolved) { result.append(resolved) }
    }
    return Array(result.prefix(2))
  }

  /// Centers: a lone button keeps the classic spot under the artwork / at the right edge.
  static func centers(count: Int, left: Bool) -> [CGFloat] {
    switch (count, left) {
    case (1, true): return [93.5]
    case (2, true): return [56, 131]
    case (1, false): return [510]
    case (2, false): return [474, 546]
    default: return []
    }
  }
}
