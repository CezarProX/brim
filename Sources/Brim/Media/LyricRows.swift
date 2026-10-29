import SwiftUI

/// Timing the active row needs to sweep on its own clock, so only that row redraws every frame.
struct LyricSweep: Equatable {
  let words: [LyricWord]
  let start: TimeInterval
  let end: TimeInterval
  let clock: ElapsedClock?
  let fixedTime: TimeInterval?
  let paused: Bool

  func time(at date: Date) -> TimeInterval { fixedTime ?? clock?.position(at: date) ?? start }
}

/// One lyric line. Same font and layout whether sung or not, so becoming active never reflows it:
/// emphasis is scale, opacity and blur, all of which animate on the GPU.
struct LyricRow: View, Equatable {
  let text: String
  /// Signed lines from the active one; nil before the first line starts.
  let distance: Int?
  let sweep: LyricSweep?
  var fontSize: CGFloat = 28
  var reduceMotion = false

  private var active: Bool { distance == 0 }
  private var far: Int { abs(distance ?? 1) }
  private var tokens: [String] { text.split(separator: " ", omittingEmptySubsequences: true).map(String.init) }

  var body: some View {
    content
      .font(.system(size: fontSize, weight: .bold))
      .frame(maxWidth: .infinity)
      .scaleEffect(active ? 1 : 0.93)
      .opacity(active ? 1 : max(far > 5 ? 0 : 0.14, 0.5 - Double(far - 1) * 0.12))
      .blur(radius: active || far > 4 || reduceMotion ? 0 : min(2.2, Double(far) * 0.6))
      .animation(reduceMotion ? nil : .spring(duration: 0.6, bounce: 0).delay(Double(max(0, min(4, distance ?? 0))) * 0.035),
                 value: distance)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(text.isEmpty ? "Instrumental" : text)
      .accessibilityHidden(!active)
  }

  @ViewBuilder private var content: some View {
    if tokens.isEmpty {
      if active, let sweep { TimedInterlude(sweep: sweep, size: fontSize) }
      else { InterludeDots(progress: 0, breath: 0, size: fontSize) }
    } else if active, let sweep, !sweep.words.isEmpty {
      TimedWords(sweep: sweep, spacing: fontSize * 0.26, reduceMotion: reduceMotion)
    } else {
      LyricWordFlow(spacing: fontSize * 0.26) {
        ForEach(Array(tokens.enumerated()), id: \.offset) { _, token in Text(token).foregroundStyle(.white) }
      }
    }
  }
}

/// The sung line: each word fills left to right over its own time, and lifts slightly as it does.
/// Syllables that touch ("May" "be") stay one word on screen and fill one after the other.
private struct TimedWords: View {
  let sweep: LyricSweep
  let spacing: CGFloat
  let reduceMotion: Bool

  var body: some View {
    let clusters = Self.clusters(sweep.words)
    TimelineView(.animation(paused: sweep.paused)) { context in
      let fills = LyricWordSynth.fills(of: sweep.words, lineEnd: sweep.end, at: sweep.time(at: context.date))
      LyricWordFlow(spacing: spacing) {
        ForEach(Array(clusters.enumerated()), id: \.offset) { _, cluster in
          HStack(spacing: 0) {
            ForEach(cluster, id: \.self) { index in
              SweptWord(text: sweep.words[index].text.trimmingCharacters(in: .whitespaces),
                        fill: fills.indices.contains(index) ? fills[index] : 0, lifts: !reduceMotion)
            }
          }
        }
      }
    }
  }

  /// Word indices grouped into on-screen words: a group ends at a word whose text ends in a space.
  static func clusters(_ words: [LyricWord]) -> [[Int]] {
    var groups: [[Int]] = []
    var current: [Int] = []
    for (index, word) in words.enumerated() {
      current.append(index)
      if word.text.last?.isWhitespace == true { groups.append(current); current = [] }
    }
    if !current.isEmpty { groups.append(current) }
    return groups
  }
}

private struct SweptWord: View {
  let text: String
  let fill: Double
  let lifts: Bool
  static let feather = 0.45

  var body: some View {
    let eased = 1 - pow(1 - fill, 3)
    Text(text)
      .foregroundStyle(.white.opacity(0.3))
      .overlay { Text(text).foregroundStyle(.white).mask(mask) }
      .offset(y: lifts ? -1.8 * eased : 0)
  }

  /// A soft leading edge that travels across the word; at 0 nothing shows, at 1 all of it.
  private var mask: LinearGradient {
    let edge = fill * (1 + Self.feather)
    let solid = min(1, max(0, edge - Self.feather))
    let clear = min(1, max(solid, edge))
    return LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: solid),
                                  .init(color: .clear, location: clear), .init(color: .clear, location: 1)],
                          startPoint: .leading, endPoint: .trailing)
  }
}

/// An instrumental break: three dots that fill across the gap and breathe while they wait.
private struct TimedInterlude: View {
  let sweep: LyricSweep
  let size: CGFloat

  var body: some View {
    TimelineView(.animation(paused: sweep.paused)) { context in
      let time = sweep.time(at: context.date)
      let progress = min(1, max(0, (time - sweep.start) / max(0.1, sweep.end - sweep.start)))
      InterludeDots(progress: progress, breath: sin(time * 2.4), size: size)
    }
  }
}

struct InterludeDots: View {
  let progress: Double
  let breath: Double
  let size: CGFloat

  var body: some View {
    HStack(spacing: size * 0.3) {
      ForEach(0..<3, id: \.self) { dot in
        let lit = min(1, max(0, progress * 3 - Double(dot)))
        Circle()
          .fill(.white.opacity(0.3 + 0.7 * lit))
          .frame(width: size * 0.32, height: size * 0.32)
      }
    }
    .scaleEffect(1 + 0.06 * breath * (progress < 1 ? 1 : 0))
    .frame(height: size * 1.2)
  }
}
