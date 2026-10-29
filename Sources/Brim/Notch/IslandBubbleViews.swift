import SwiftUI

/// iPhone's minimal presentation, measured from its bubble: a black circle as tall as the island,
/// one glyph or a two-to-three character readout, and progress drawn as a thin ring 2pt inside the edge.
enum IslandBubbleMetrics {
  /// Gap between the bubble's edge and its ring.
  static let ringInset: CGFloat = 2
  /// 2pt on the pill's bubble, 1.75pt on the notch's smaller one so the readout keeps its air.
  static let ringWidth: CGFloat = 2
  static func ringWidth(_ diameter: CGFloat) -> CGFloat { diameter < 35 ? 1.75 : ringWidth }
  /// Letter-spacing of the readout's digits.
  static let valueTracking: CGFloat = -0.3
  /// The readout: SF Rounded semibold, 11pt in the notch's 32pt bubble and 12pt in the pill's
  /// 37pt one, the unit at 60% beside it. Two digits and a unit then stay inside the
  /// ring's clear disc with a point to spare on each side.
  static let valueSize: CGFloat = 12
  static func valueSize(_ diameter: CGFloat) -> CGFloat { min(valueSize, (diameter * 0.345).rounded(.down)) }
  static func unitSize(_ diameter: CGFloat) -> CGFloat { (valueSize(diameter) * 1.2).rounded() / 2 }
  /// A single glyph fills about half the circle.
  static func glyphSize(_ diameter: CGFloat) -> CGFloat { (diameter * 0.47).rounded() }
  /// The clear disc inside the ring, where readouts must stay.
  static func innerDiameter(_ diameter: CGFloat) -> CGFloat { diameter - 2 * (ringInset + ringWidth(diameter)) }
}

/// A thin progress ring hugging the bubble's inner edge, with a faint track.
struct IslandBubbleRing: View {
  /// 0...1; nil draws the track only (progress unknown).
  let progress: Double?
  var tint: Color
  let diameter: CGFloat
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    let width = IslandBubbleMetrics.ringWidth(diameter)
    let inset = IslandBubbleMetrics.ringInset + width / 2
    ZStack {
      Circle().inset(by: inset).stroke(tint.opacity(0.25), lineWidth: width)
      if let progress {
        Circle().inset(by: inset)
          .trim(from: 0, to: max(0, min(1, progress.isFinite ? progress : 0)))
          .stroke(tint, style: StrokeStyle(lineWidth: width, lineCap: .round))
          .rotationEffect(.degrees(-90))
          .animation(reduceMotion ? nil : .linear(duration: 1), value: progress)
      }
    }
    .accessibilityHidden(true)
  }
}

/// A countdown in its bubble: the ring empties as time runs out, the time left sits in the middle
/// ("24m", then "42s" in the timer's colour for the last minute), a pause glyph while paused and a
/// check once done.
struct TimerBubble: View {
  let remaining: TimeInterval
  let duration: TimeInterval
  let paused: Bool
  var done = false
  var tint: Color = IslandTint.timer
  let diameter: CGFloat

  var body: some View {
    let state = Self.state(remaining: remaining, paused: paused, done: done)
    ZStack {
      IslandBubbleRing(progress: done ? 1 : remaining / max(1, duration), tint: tint, diameter: diameter)
        .opacity(state == .paused ? 0.5 : 1)
      switch state {
      case .done, .paused:
        Image(systemName: state == .done ? "checkmark" : "pause.fill")
          .font(.system(size: IslandBubbleMetrics.valueSize - 1, weight: .bold))
          .foregroundStyle(tint)
          .contentTransition(.symbolEffect(.replace))
      case .running, .nearEnd:
        let readout = Self.readout(remaining)
        HStack(alignment: .firstTextBaseline, spacing: 0) {
          Text(readout.value)
            .font(.system(size: IslandBubbleMetrics.valueSize(diameter), weight: .semibold, design: .rounded))
            .tracking(IslandBubbleMetrics.valueTracking)
            .contentTransition(.numericText(countsDown: true))
          Text(readout.unit)
            .font(.system(size: IslandBubbleMetrics.unitSize(diameter), weight: .semibold, design: .rounded))
            .opacity(0.7)
        }
        .monospacedDigit()
        .foregroundStyle(state == .nearEnd ? tint : .white)
        .fixedSize()
      }
    }
    .frame(width: diameter, height: diameter)
    .accessibilityHidden(true)
  }

  enum State: Equatable { case running, nearEnd, paused, done }

  static func state(remaining: TimeInterval, paused: Bool, done: Bool) -> State {
    if done { return .done }
    if paused { return .paused }
    return remaining < 60 ? .nearEnd : .running
  }

  /// What fits inside the ring: hours, else minutes (rounded up, as the Clock app counts them), else
  /// seconds for the last minute. The ring carries the precision.
  static func readout(_ remaining: TimeInterval) -> (value: String, unit: String) {
    let seconds = Int(max(0, min(remaining.isFinite ? remaining : 0, 359_999)).rounded(.up))
    if seconds < 60 { return ("\(seconds)", "s") }
    let minutes = (seconds + 59) / 60
    if minutes < 60 { return ("\(minutes)", "m") }
    return ("\(max(1, seconds / 3600))", "h")
  }

  static func text(_ remaining: TimeInterval) -> String {
    let readout = readout(remaining)
    return readout.value + readout.unit
  }
}

/// A coding agent in its bubble: its mascot, and a small dot for its state (working, waiting on
/// you, finished).
struct AgentBubble: View {
  let tool: CodingAgentSession.Tool
  let state: Status
  let diameter: CGFloat

  enum Status: Equatable { case working, needsInput, finished }

  var body: some View {
    let mark = (diameter * 0.52).rounded()
    let dot: CGFloat = 6
    // The dot sits on the mascot's lower-right shoulder, inside the circle.
    let offset = diameter * 0.22
    ZStack {
      Group {
        if tool == .claude, let clawd = ClaudeArt.clawd {
          Image(nsImage: clawd).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
        } else {
          AgentMascot(tool: tool, size: mark)
        }
      }
      .frame(width: mark, height: mark)
      Circle().fill(color)
        .frame(width: dot, height: dot)
        .padding(1.5).background(.black, in: Circle())
        .offset(x: offset, y: offset)
        .animation(.spring(duration: 0.35, bounce: 0.3), value: state)
    }
    .frame(width: diameter, height: diameter)
    .accessibilityHidden(true)
  }

  private var color: Color {
    switch state {
    case .working: return IslandTint.color(for: .agent)
    case .needsInput: return .orange
    case .finished: return .green
    }
  }
}

/// The song in its bubble: the cover as a disc, or the waveform when there is no cover.
struct MusicBubble: View {
  let artwork: NSImage?
  let isPlaying: Bool
  let diameter: CGFloat

  var body: some View {
    Group {
      if let artwork {
        Image(nsImage: artwork).resizable().interpolation(.high).scaledToFill()
          .frame(width: diameter - 10, height: diameter - 10)
          .clipShape(Circle())
          .opacity(isPlaying ? 1 : 0.6)
      } else {
        PlaybackWaveform(isPlaying: isPlaying).frame(width: 18, height: 16)
      }
    }
    .frame(width: diameter, height: diameter)
    .accessibilityHidden(true)
  }
}

/// A download in its bubble: the ring fills, an arrow in the middle.
struct DownloadBubble: View {
  let fraction: Double?
  let diameter: CGFloat

  var body: some View {
    let tint = IslandTint.color(for: .download)
    ZStack {
      IslandBubbleRing(progress: fraction, tint: tint, diameter: diameter)
      Image(systemName: "arrow.down")
        .font(.system(size: IslandBubbleMetrics.valueSize - 1, weight: .bold))
        .foregroundStyle(tint)
    }
    .frame(width: diameter, height: diameter)
    .accessibilityHidden(true)
  }
}

/// What a bubble shows for each activity; everything without a minimal form of its own shows its
/// compact glyph.
@MainActor
struct IslandBubbleContent<Fallback: View>: View {
  let activity: IslandActivity
  let diameter: CGFloat
  @ObservedObject var nowPlaying: NowPlayingModel
  @ObservedObject var timers: NativeTimerModel
  @ObservedObject var extensions: ActivityCenter
  @ViewBuilder var fallback: Fallback

  var body: some View {
    switch activity {
    case .music:
      MusicBubble(artwork: nowPlaying.track?.artwork, isPlaying: nowPlaying.track?.isPlaying == true,
                  diameter: diameter)
    case .timer:
      if let timer = timers.activeTimer {
        TimelineView(.periodic(from: .now, by: 1)) { context in
          TimerBubble(remaining: timer.remaining(at: context.date), duration: timer.duration,
                      paused: timer.isPaused, diameter: diameter)
        }
      }
    case .focus:
      let focus = extensions.focus
      TimelineView(.periodic(from: .now, by: 1)) { context in
        TimerBubble(remaining: focus.remaining(at: context.date), duration: focus.duration,
                    paused: focus.isPaused, done: focus.completed,
                    tint: focus.phase == .rest ? .green : SessionColor.current.color, diameter: diameter)
      }
    case .agent where extensions.coding.session?.isLive() == true:
      if let session = extensions.coding.session {
        AgentBubble(tool: session.tool, state: Self.agentStatus(session), diameter: diameter)
      }
    case .download where extensions.downloads.active != nil:
      DownloadBubble(fraction: extensions.downloads.active?.fraction, diameter: diameter)
    case .recording:
      Circle().fill(IslandTint.recording).frame(width: 11, height: 11)
    default:
      fallback.frame(width: IslandBubbleMetrics.glyphSize(diameter) + 4,
                     height: IslandBubbleMetrics.glyphSize(diameter) + 4)
    }
  }

  static func agentStatus(_ session: CodingAgentSession) -> AgentBubble.Status {
    session.needsAttention ? .needsInput : session.isWorking ? .working : .finished
  }
}

/// The bubble pinching off the island's side, like iPhone's: it grows out from under the edge,
/// stretched a little along the split, and settles round. Reduce Motion fades it instead.
struct IslandBubbleSplit: ViewModifier {
  let progress: CGFloat
  let side: IslandBubbleSide
  /// How far the bubble travels out from the island (its own width plus the gap).
  let travel: CGFloat

  func body(content: Content) -> some View {
    let remaining = 1 - progress
    let direction: CGFloat = side == .trailing ? 1 : -1
    content
      .scaleEffect(x: 0.45 + 0.55 * progress + 0.25 * remaining * progress, y: 0.45 + 0.55 * progress,
                   anchor: side == .trailing ? .leading : .trailing)
      .offset(x: -direction * travel * remaining)
      .blur(radius: 3 * remaining)
      .opacity(Double(min(1, progress * 2)))
  }
}

extension AnyTransition {
  static func islandBubble(_ side: IslandBubbleSide, travel: CGFloat, reduceMotion: Bool) -> AnyTransition {
    if reduceMotion { return .opacity }
    return .asymmetric(
      insertion: .modifier(active: IslandBubbleSplit(progress: 0, side: side, travel: travel),
                           identity: IslandBubbleSplit(progress: 1, side: side, travel: travel)),
      removal: .modifier(active: IslandBubbleSplit(progress: 0, side: side, travel: travel * 0.6),
                         identity: IslandBubbleSplit(progress: 1, side: side, travel: travel * 0.6)))
  }
}
