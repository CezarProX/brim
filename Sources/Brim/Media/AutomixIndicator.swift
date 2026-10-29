import SwiftUI

/// Two interlocked rings: the Automix mark. `progress` 0...1 morphs it from nothing to full size.
struct AutomixRings: View {
  var progress: Double
  var tint: Color = .white

  var body: some View {
    GeometryReader { proxy in
      let size = min(proxy.size.width, proxy.size.height)
      let diameter = size * 0.62
      let line = max(1.6, size * 0.1)
      let offset = diameter * 0.36 * progress
      ZStack {
        Circle().strokeBorder(tint, lineWidth: line).frame(width: diameter, height: diameter).offset(x: -offset)
        Circle().strokeBorder(tint.opacity(0.7), lineWidth: line).frame(width: diameter, height: diameter).offset(x: offset)
      }
      .frame(width: proxy.size.width, height: proxy.size.height)
      .opacity(min(1, max(0, (progress - 0.35) / 0.5)))
      .scaleEffect(0.6 + 0.4 * progress)
    }
    .accessibilityHidden(true)
  }
}

/// Compact-island waveform slot: the normal waveform, morphing into the Automix rings while Music mixes
/// into the next song. With the setting off (or nothing to mix) it is exactly `PlaybackWaveform`.
struct AutomixWaveformSlot: View {
  let track: NowPlayingTrack
  var tint: Color?
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var preference = AutomixDetector.musicCrossfadePreference()

  var body: some View {
    if AppSettings.shared.mediaAutomixIndicator, track.snapshot.source == .music {
      TimelineView(.periodic(from: .now, by: 0.5)) { context in
        let value = AutomixDetector.progress(AutomixDetector.Input(
          isMusicApp: true, isPlaying: track.isPlaying, position: track.position(at: context.date),
          duration: track.duration, crossfadeEnabled: preference.enabled, crossfadeSeconds: preference.seconds))
        AutomixMorph(progress: value, waveform: PlaybackWaveform(isPlaying: track.isPlaying, colored: true, tint: tint), tint: tint ?? .white)
          .animation(reduceMotion ? nil : .smooth(duration: 0.6), value: value > 0)
      }
      .onAppear { preference = AutomixDetector.musicCrossfadePreference() }
    } else {
      PlaybackWaveform(isPlaying: track.isPlaying, colored: true, tint: tint)
    }
  }
}

/// Pure presentation of the morph, so it can be rendered with any progress.
struct AutomixMorph<Waveform: View>: View {
  let progress: Double
  let waveform: Waveform
  var tint: Color = .white

  var body: some View {
    ZStack {
      waveform.opacity(max(0, 1 - progress * 2.4)).scaleEffect(1 - 0.35 * progress).blur(radius: 2 * progress)
      AutomixRings(progress: progress, tint: tint)
    }
    .frame(width: 23, height: 20)
  }
}
