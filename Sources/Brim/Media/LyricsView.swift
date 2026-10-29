import SwiftUI

/// Scrolling timed lyrics for the player drawer. The active line is bright and larger,
/// its neighbours fade; with word timing the sung words light up as they pass.
/// Laid out in the player's 600-point reference space.
struct LyricsView: View {
  @ObservedObject var model: LyricsModel
  let track: NowPlayingTrack
  /// Test hook: pins the clock instead of following the track.
  var fixedTime: TimeInterval?
  /// Frame height in the 600-point reference space (the drawer by default).
  var height: CGFloat = MusicPlayerLayout.drawerHeight

  var body: some View {
    Group {
      switch model.state {
      case .ready(let lyrics): synced(lyrics)
      case .loading: placeholder("Finding lyrics…", symbol: "text.quote", spinner: true)
      case .none: placeholder("No lyrics", symbol: "text.quote")
      case .off: placeholder("Lyrics are off", symbol: "text.quote")
      }
    }
    .frame(width: 600, height: height)
    .accessibilityElement(children: .contain)
  }

  /// The line index only needs checking a few times a beat; the sung row runs its own 60 fps clock.
  private func synced(_ lyrics: TimedLyrics) -> some View {
    let paused = fixedTime == nil && !track.isPlaying
    return TimelineView(.animation(minimumInterval: 0.04, paused: paused)) { context in
      let time = fixedTime ?? track.position(at: context.date)
      LyricsScroller(lyrics: lyrics, index: lyrics.index(at: time, lookahead: 0.12),
                     clock: fixedTime == nil ? track.clock : nil, fixedTime: fixedTime, paused: paused)
    }
    .id("\(lyrics.lines.first?.id ?? "")|\(lyrics.lines.count)")
  }

  private func placeholder(_ text: String, symbol: String, spinner: Bool = false) -> some View {
    VStack(spacing: 10) {
      if spinner { ProgressView().controlSize(.regular) }
      else { Image(systemName: symbol).font(.system(size: 30, weight: .medium)) }
      Text(text).font(.system(size: 22, weight: .medium))
    }
    .foregroundStyle(IslandInk.tertiary)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .accessibilityLabel(text)
  }
}

private struct LyricsScroller: View {
  let lyrics: TimedLyrics
  let index: Int?
  let clock: ElapsedClock?
  let fixedTime: TimeInterval?
  let paused: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    LyricsColumnLayout(position: Double(index ?? 0), spacing: 14, cascade: reduceMotion ? 0 : 0.07) {
      ForEach(Array(lyrics.lines.enumerated()), id: \.offset) { offset, line in
        LyricRow(text: line.text, distance: index.map { offset - $0 },
                 sweep: offset == index ? sweep(at: offset) : nil, reduceMotion: reduceMotion)
          .equatable()
      }
    }
    .padding(.horizontal, 44)
    .animation(reduceMotion ? nil : .spring(duration: 0.7, bounce: 0), value: index)
    .clipped()
    .mask(fade)
  }

  private func sweep(at offset: Int) -> LyricSweep {
    // Only real word timing sweeps; a line-timed song lights whole lines, as Spotify does.
    LyricSweep(words: lyrics.lines[offset].words, start: lyrics.lines[offset].time,
               end: lyrics.sweepEnd(at: offset), clock: clock, fixedTime: fixedTime, paused: paused)
  }

  private var fade: some View {
    LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.2),
                           .init(color: .black, location: 0.8), .init(color: .clear, location: 1)],
                   startPoint: .top, endPoint: .bottom)
  }
}
