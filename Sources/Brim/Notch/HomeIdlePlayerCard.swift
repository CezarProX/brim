import AppKit
import SwiftUI

/// Home's Media widget, and the Music page's card while no track is known: the "Not playing"
/// card, a grey artwork tile with a note glyph, the title, and the transport.
/// Medium: artwork beside title and artist, transport centred underneath (previous and next once a
/// song is known). Small: the artwork tile with a play/pause button on its shoulder, title beneath.
@MainActor
struct HomeIdlePlayerCard: View {
  @ObservedObject var model: NowPlayingModel
  var size: HomeWidgetSize = .medium
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    HomeWidgetCard(fill: Color.white.opacity(0.10)) {
      if size == .small { small } else { medium }
    }
    .accessibilityElement(children: .contain)
  }

  private var title: String { model.track?.snapshot.title ?? String(localized: "Not playing") }
  private var artist: String? {
    guard let artist = model.track?.snapshot.artist, !artist.isEmpty else { return nil }
    return artist
  }

  private var medium: some View {
    VStack(spacing: 0) {
      HStack(spacing: 12) {
        artwork(side: 62)
        VStack(alignment: .leading, spacing: 2) {
          Text(title).font(IslandFont.title).foregroundStyle(IslandInk.primary).lineLimit(1)
          if let artist {
            Text(artist).font(IslandFont.label).foregroundStyle(IslandInk.secondary).lineLimit(1)
          }
        }
        Spacer(minLength: 0)
      }
      Spacer(minLength: 0)
      HStack(spacing: 18) {
        if model.track != nil {
          transportButton("backward.fill", label: "Previous") { model.previous() }
        }
        playButton(side: 34)
        if model.track != nil {
          transportButton("forward.fill", label: "Next") { model.next() }
        }
      }
    }
  }

  private var small: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .top, spacing: 0) {
        artwork(side: 56)
        Spacer(minLength: 4)
        playButton(side: 30)
      }
      Spacer(minLength: 6)
      Text(title).font(IslandFont.headline).foregroundStyle(IslandInk.primary).lineLimit(1)
      Text(artist ?? String(localized: "Music"))
        .font(IslandFont.label).foregroundStyle(IslandInk.secondary).lineLimit(1)
    }
  }

  /// The playing song's own cover, else the remembered one (which only catches up with a new song
  /// on the next poll, so on its own it showed a blank tile right after the song changed).
  static func cover(for model: NowPlayingModel) -> NSImage? {
    guard let track = model.track else { return nil }
    return track.artwork ?? model.lastArtwork
  }

  private func artwork(side: CGFloat) -> some View {
    RoundedRectangle(cornerRadius: IslandRadius.medium, style: .continuous)
      .fill(Color.white.opacity(0.10))
      .frame(width: side, height: side)
      .overlay {
        if let image = Self.cover(for: model) {
          Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: IslandRadius.medium, style: .continuous))
        } else {
          Image(systemName: "music.note").font(.system(size: side * 0.38, weight: .semibold))
            .foregroundStyle(IslandInk.tertiary)
        }
      }
  }

  /// Optimistic: while macOS is starting the song the button already shows pause.
  private var showsPlaying: Bool {
    model.track.map(\.isPlaying) ?? model.isStartingPlayback
  }

  private func playButton(side: CGFloat) -> some View {
    let playing = showsPlaying
    return Button(action: tapped) {
      Image(systemName: playing ? "pause.fill" : "play.fill").font(.system(size: side * 0.38, weight: .bold))
        .contentTransition(.symbolEffect(.replace))
        .foregroundStyle(IslandInk.primary)
        .frame(width: side, height: side)
        .background(IslandFill.raised, in: Circle())
    }
    .buttonStyle(IslandPressStyle(pressedScale: 0.88))
    .accessibilityLabel(playing ? "Pause" : "Play")
  }

  private func transportButton(_ symbol: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: symbol).font(.system(size: 13, weight: .bold)).foregroundStyle(IslandInk.secondary)
        .frame(width: 30, height: 30).contentShape(Circle())
    }
    .buttonStyle(IslandPressStyle(pressedScale: 0.86))
    .accessibilityLabel(label)
  }

  /// Like the Mac's play key: the system resumes whatever last played, in place. The button flips at
  /// once; the stream's song then fills the card.
  private func tapped() {
    withAnimation(NotchMotion.press(reduceMotion: reduceMotion)) { model.playFromIdle() }
  }
}
