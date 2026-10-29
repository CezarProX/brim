import SwiftUI

/// Home widget: the current song's synced lyrics. The active line is bright and larger, its
/// neighbours dim, and it advances with the song. Reads `LyricsModel`; never writes to it.
struct HomeLyricsWidget: View {
  @ObservedObject var model: LyricsModel
  @ObservedObject var nowPlaying: NowPlayingModel
  /// Test hook: pins the clock instead of following the track.
  var fixedTime: TimeInterval?

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HomeWidgetHeader(title: "Lyrics", symbol: "quote.bubble.fill")
      content.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  @ViewBuilder private var content: some View {
    switch model.state {
    case .ready(let lyrics): synced(lyrics)
    case .loading: message("Finding lyrics…")
    case .none: message("No lyrics")
    case .off: off
    }
  }

  private func synced(_ lyrics: TimedLyrics) -> some View {
    TimelineView(.animation(minimumInterval: 0.25, paused: fixedTime == nil && nowPlaying.track?.isPlaying != true)) { context in
      let time = fixedTime ?? nowPlaying.track?.position(at: context.date) ?? 0
      let index = lyrics.index(at: time, lookahead: 0.12)
      VStack(spacing: 5) {
        ForEach(Self.visibleOffsets(index: index, count: lyrics.lines.count), id: \.self) { offset in
          line(lyrics, offset: offset, active: offset == index, time: time)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .animation(.spring(duration: 0.4, bounce: 0.1), value: index)
    }
  }

  /// Previous, active and next line; before the first line starts, the first two.
  static func visibleOffsets(index: Int?, count: Int) -> [Int] {
    guard count > 0 else { return [] }
    guard let index else { return Array(0..<min(2, count)) }
    return Array(max(0, index - 1)...min(count - 1, index + 1))
  }

  private func line(_ lyrics: TimedLyrics, offset: Int, active: Bool, time: TimeInterval) -> some View {
    let text = lyrics.lines[offset].text
    return Group {
      if text.isEmpty {
        Image(systemName: "music.note")
      } else if active, !lyrics.lines[offset].words.isEmpty {
        sung(lyrics.lines[offset].words, time: time)
      } else {
        Text(text)
      }
    }
    .font(.system(size: active ? 16 : 12, weight: active ? .bold : .semibold))
    .foregroundStyle(active ? IslandInk.primary : IslandInk.secondary)
    .opacity(active ? 1 : 0.5)
    .multilineTextAlignment(.center)
    .lineLimit(2)
    .minimumScaleFactor(0.8)
    .frame(maxWidth: .infinity)
    .accessibilityHidden(!active)
  }

  private func sung(_ words: [LyricWord], time: TimeInterval) -> Text {
    let reached = LyricWordSynth.activeIndex(in: words, at: time) ?? -1
    return words.enumerated().reduce(Text("")) { text, entry in
      text + Text(entry.element.text).foregroundColor(entry.offset <= reached ? .white : .white.opacity(0.45))
    }
  }

  private var off: some View {
    VStack(spacing: 6) {
      Text("Lyrics are off").font(IslandFont.label).foregroundStyle(IslandInk.secondary)
      Button("Turn on") {
        AppSettings.shared.lyricsEnabled = true
        MediaServices.shared.sync()
      }
      .font(IslandFont.caption.weight(.semibold)).buttonStyle(IslandPressStyle())
      .foregroundStyle(IslandInk.primary)
    }
  }

  private func message(_ text: LocalizedStringKey) -> some View {
    Text(text).font(IslandFont.label).foregroundStyle(IslandInk.tertiary)
  }
}
