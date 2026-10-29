import AppKit
import AVFoundation
import SwiftUI

/// The tint a Pomodoro session wears in the ring and tape.
enum SessionColor: String, CaseIterable, Identifiable {
  case orange, red, green, blue, purple, pink, mint
  var id: String { rawValue }
  var color: Color {
    switch self {
    case .orange: .orange
    case .red: Color(red: 1, green: 0.27, blue: 0.23)
    case .green: .green
    case .blue: .blue
    case .purple: .purple
    case .pink: .pink
    case .mint: .mint
    }
  }
  static var current: SessionColor { SessionColor(rawValue: AppSettings.shared.pomodoroColorName) ?? .orange }
}

enum PomodoroEndSound: String, CaseIterable, Identifiable {
  case none, glass, hero, ping, submarine, tink
  var id: String { rawValue }
  var title: String { self == .none ? "None" : rawValue.capitalized }
  @MainActor func play() { if self != .none { NSSound(named: NSSound.Name(rawValue.capitalized))?.play() } }
  static var current: PomodoroEndSound { PomodoroEndSound(rawValue: AppSettings.shared.pomodoroEndSoundName) ?? .glass }
}

enum AmbientSound: String, CaseIterable, Identifiable {
  case off, brown, pink, rain
  var id: String { rawValue }
  var title: String {
    switch self {
    case .off: "Off"
    case .brown: "Brown noise"
    case .pink: "Pink noise"
    case .rain: "Rain"
    }
  }
  static var current: AmbientSound { AmbientSound(rawValue: AppSettings.shared.pomodoroAmbientName) ?? .off }
}

/// Noise sample generator; outputs stay within -1...1.
struct NoiseGenerator {
  let kind: AmbientSound
  private var last: Float = 0
  private var pink: (b0: Float, b1: Float, b2: Float) = (0, 0, 0)
  private var rng = SystemRandomNumberGenerator()

  init(kind: AmbientSound) { self.kind = kind }

  mutating func next() -> Float {
    let white = Float.random(in: -1...1, using: &rng)
    switch kind {
    case .off: return 0
    case .brown:
      last = max(-1, min(1, (last + 0.02 * white) / 1.02))
      return last * 3.5 > 1 ? 1 : (last * 3.5 < -1 ? -1 : last * 3.5)
    case .pink:
      pink.b0 = 0.99765 * pink.b0 + white * 0.0990460
      pink.b1 = 0.96300 * pink.b1 + white * 0.2965164
      pink.b2 = 0.57000 * pink.b2 + white * 1.0526913
      return max(-1, min(1, (pink.b0 + pink.b1 + pink.b2 + white * 0.1848) * 0.25))
    case .rain:
      // Bright, lightly smoothed noise reads as steady rain.
      last = 0.6 * last + 0.4 * white
      return last
    }
  }
}

/// Plays quiet looping noise while a focus phase runs. On-device, no files.
@MainActor
final class AmbientSoundPlayer {
  static let shared = AmbientSoundPlayer()
  private var engine: AVAudioEngine?
  private(set) var playing: AmbientSound = .off

  func play(_ kind: AmbientSound, volume: Float = 0.12) {
    guard kind != playing else { return }
    stop()
    guard kind != .off else { return }
    let engine = AVAudioEngine()
    var generator = NoiseGenerator(kind: kind)
    let node = AVAudioSourceNode { _, _, frames, buffers in
      let list = UnsafeMutableAudioBufferListPointer(buffers)
      for frame in 0..<Int(frames) {
        let value = generator.next() * volume
        for buffer in list { buffer.mData?.assumingMemoryBound(to: Float.self)[frame] = value }
      }
      return noErr
    }
    engine.attach(node)
    engine.connect(node, to: engine.mainMixerNode, format: engine.outputNode.inputFormat(forBus: 0))
    do {
      try engine.start()
      self.engine = engine
      playing = kind
    } catch { playing = .off }
  }

  func stop() {
    engine?.stop()
    engine = nil
    playing = .off
  }
}
