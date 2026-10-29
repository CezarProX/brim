import SwiftUI

/// Pieces for the compact music activity. The shell composes them: artwork in the left
/// wing (wrapped in `TrackSwipeSurface`), `CompactTrackTitle` where a title is allowed and
/// `PlaybackWaveform` (live or synthetic) in the right wing.
struct CompactArtwork: View {
  let image: NSImage?
  var size: CGFloat = 20

  var body: some View {
    TrackSwipeSurface {
      MusicArtworkView(image: image, cornerRadius: size * 0.26)
        .frame(width: size, height: size)
    }
  }
}

struct CompactTrackTitle: View {
  let track: NowPlayingTrack
  var hasNotch: Bool
  var width: CGFloat = 96

  var body: some View {
    if let text = CompactTitlePolicy.text(hasNotch: hasNotch, title: track.title,
                                          artist: track.artist, settings: .shared) {
      MarqueeText(text: text, font: IslandFont.label.weight(.semibold), color: IslandInk.primary)
        .frame(width: width)
    }
  }
}
