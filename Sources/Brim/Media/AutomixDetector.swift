import Foundation

/// Best-effort "is the next transition a mix?" for Apple Music. Music exposes no Automix state to
/// scripting, so this uses its Crossfade preference (`com.apple.Music`: crossfadeEnabled / crossfadeSeconds)
/// and the position in the song: it is true over the final stretch, and the first seconds of the next song.
enum AutomixDetector {
  /// Seconds before the crossfade begins that the indicator starts morphing in.
  static let leadIn: TimeInterval = 3

  struct Input: Equatable {
    var isMusicApp: Bool
    var isPlaying: Bool
    var position: TimeInterval
    var duration: TimeInterval
    var crossfadeEnabled: Bool
    var crossfadeSeconds: TimeInterval
    var hasNext: Bool = true
  }

  /// 0 = plain waveform, 1 = fully rings. Ramps up as the mix approaches.
  static func progress(_ input: Input) -> Double {
    guard input.isMusicApp, input.isPlaying, input.crossfadeEnabled, input.hasNext,
          input.duration > 0, input.position.isFinite else { return 0 }
    let fade = min(max(input.crossfadeSeconds, 1), 12)
    let remaining = input.duration - input.position
    guard remaining > 0 else { return 0 }
    let window = fade + leadIn
    if remaining <= window { return min(1, max(0, 1 - (remaining - fade) / leadIn)) }
    // Just after a mix landed: hold the rings, then fade them out.
    if input.position < fade { return min(1, max(0, 1 - input.position / fade)) }
    return 0
  }

  static func isMixing(_ input: Input) -> Bool { progress(input) > 0 }

  /// Reads Music's crossfade preference. Returns (enabled, seconds).
  static func musicCrossfadePreference() -> (enabled: Bool, seconds: TimeInterval) {
    let domain = "com.apple.Music" as CFString
    let enabled = (CFPreferencesCopyAppValue("crossfadeEnabled" as CFString, domain) as? NSNumber)?.boolValue ?? false
    let seconds = (CFPreferencesCopyAppValue("crossfadeSeconds" as CFString, domain) as? NSNumber)?.doubleValue ?? 6
    return (enabled, seconds)
  }

  static func input(for track: NowPlayingTrack, position: TimeInterval) -> Input {
    let preference = musicCrossfadePreference()
    return Input(
      isMusicApp: track.snapshot.source == .music, isPlaying: track.isPlaying, position: position,
      duration: track.duration, crossfadeEnabled: preference.enabled, crossfadeSeconds: preference.seconds)
  }
}
