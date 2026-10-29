import SwiftUI

/// The hero Now Playing tile, as Control Center's Now Playing module: the cover (which settles
/// back while paused, as in Music), a live equalizer, the song's progress and the transport.
/// Wide is one row: cover, titles, transport.
struct NowPlayingTileView: View {
  let size: TileSize
  @ObservedObject var model: NowPlayingModel
  @State private var skips = (back: 0, forward: 0)
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    let track = model.track
    CommandTileSurface {
      if let track {
        if size == .hero { hero(track) } else { wide(track) }
      } else {
        idle
      }
    }
    .animation(reduceMotion ? nil : .spring(duration: 0.45, bounce: 0.25), value: track?.isPlaying)
    .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: track?.title)
  }

  private func tint(_ track: NowPlayingTrack) -> Color { ArtworkTint.color(for: track.artwork) ?? .pink }

  private func hero(_ track: NowPlayingTrack) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .top) {
        artwork(track, side: 64)
        Spacer(minLength: 0)
        EqualizerBars(playing: track.isPlaying, tint: tint(track))
      }
      Spacer(minLength: 0)
      titles(track)
      ProgressLine(track: track, tint: tint(track)).padding(.top, 7)
      controls(track).padding(.top, 4)
    }
  }

  private func wide(_ track: NowPlayingTrack) -> some View {
    HStack(spacing: 10) {
      artwork(track, side: 52)
      titles(track)
      Spacer(minLength: 0)
      controls(track)
    }
    .frame(maxHeight: .infinity)
  }

  private var idle: some View {
    VStack(alignment: .leading, spacing: 6) {
      TileGlyph(symbol: "music.note", size: size == .hero ? 40 : 34)
      Spacer(minLength: 0)
      Text("Nothing playing").font(IslandFont.headline).foregroundStyle(IslandInk.primary)
      Text("Play something in Music or Spotify").font(IslandFont.caption).foregroundStyle(IslandInk.secondary)
    }
  }

  private func titles(_ track: NowPlayingTrack) -> some View {
    VStack(alignment: .leading, spacing: 1) {
      Text(track.title).font(IslandFont.headline).foregroundStyle(IslandInk.primary).lineLimit(1)
      Text(track.artist.isEmpty ? track.sourceName : track.artist).font(IslandFont.caption)
        .foregroundStyle(IslandInk.secondary).lineLimit(1)
    }
    .id(track.title)
    .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
  }

  private func controls(_ track: NowPlayingTrack) -> some View {
    HStack(spacing: size == .hero ? 18 : 10) {
      transport("backward.fill", bounce: skips.back) { skips.back += 1; model.previous() }
      transport(track.isPlaying ? "pause.fill" : "play.fill", big: true, bounce: 0) { model.playPause() }
      transport("forward.fill", bounce: skips.forward) { skips.forward += 1; model.next() }
    }
    .frame(maxWidth: size == .hero ? .infinity : nil)
  }

  private func transport(_ symbol: String, big: Bool = false, bounce: Int, _ action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: symbol).font(.system(size: big ? 20 : 14, weight: .semibold))
        .foregroundStyle(IslandInk.primary)
        .contentTransition(.symbolEffect(.replace.downUp))
        .symbolEffect(.bounce.byLayer, value: bounce)
        .frame(width: big ? 34 : 30, height: 28).contentShape(Rectangle())
    }
    .buttonStyle(IslandPressStyle(pressedScale: 0.82))
  }

  @ViewBuilder
  private func artwork(_ track: NowPlayingTrack, side: CGFloat) -> some View {
    Group {
      if let art = track.artwork {
        Image(nsImage: art).resizable().scaledToFill()
      } else {
        Rectangle().fill(Color.pink.opacity(0.35)).overlay(Image(systemName: "music.note").foregroundStyle(.white))
      }
    }
    .frame(width: side, height: side).clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    .overlay { RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 0.5) }
    .shadow(color: .black.opacity(track.isPlaying ? 0.45 : 0.25), radius: track.isPlaying ? 9 : 4, y: track.isPlaying ? 5 : 2)
    .scaleEffect(track.isPlaying ? 1 : 0.9, anchor: .topLeading)
  }
}

/// Four bars that dance while music plays and rest low when it is paused.
struct EqualizerBars: View {
  let playing: Bool
  var tint: Color = .pink
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private static let phases: [Double] = [0, 1.7, 0.6, 2.4]
  private static let speeds: [Double] = [7.1, 9.3, 6.2, 8.4]

  var body: some View {
    TimelineView(.animation(minimumInterval: 1 / 30, paused: !playing || reduceMotion)) { context in
      let time = context.date.timeIntervalSinceReferenceDate
      HStack(alignment: .bottom, spacing: 2) {
        ForEach(0..<4, id: \.self) { index in
          Capsule().fill(tint.gradient)
            .frame(width: 3, height: 16 * level(index, time: time))
        }
      }
      .frame(width: 18, height: 16, alignment: .bottom)
    }
    .animation(.spring(duration: 0.4), value: playing)
    .accessibilityHidden(true)
  }

  private func level(_ index: Int, time: Double) -> CGFloat {
    guard playing, !reduceMotion else { return 0.22 }
    let wave = sin(time * Self.speeds[index] + Self.phases[index]) * 0.5 + 0.5
    let flutter = sin(time * Self.speeds[index] * 1.9 + Self.phases[index] * 2) * 0.5 + 0.5
    return CGFloat(0.25 + 0.75 * (wave * 0.7 + flutter * 0.3))
  }
}

/// A thin track-progress line that follows the song's clock.
private struct ProgressLine: View {
  let track: NowPlayingTrack
  let tint: Color

  var body: some View {
    TimelineView(.periodic(from: .now, by: 0.5)) { context in
      let fraction = track.duration > 0 ? min(1, max(0, track.position(at: context.date) / track.duration)) : 0
      GeometryReader { proxy in
        ZStack(alignment: .leading) {
          Capsule().fill(Color.white.opacity(0.16))
          Capsule().fill(Color.white.opacity(0.9))
            .frame(width: max(3, proxy.size.width * fraction))
            .shadow(color: tint.opacity(0.6), radius: 3)
        }
      }
      .frame(height: 3)
      .animation(.linear(duration: 0.5), value: fraction)
    }
    .accessibilityHidden(true)
  }
}
