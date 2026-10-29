import AppKit
import SwiftUI

enum AudioQuality: String, Equatable, Sendable {
  case lossless, hiRes, atmos

  var title: String {
    switch self {
    case .lossless: return "Lossless"
    case .hiRes: return "Hi-Res Lossless"
    case .atmos: return "Dolby Atmos"
    }
  }
  var symbol: String {
    switch self {
    case .lossless, .hiRes: return "waveform"
    case .atmos: return "speaker.wave.3.fill"
    }
  }

  /// Classify from whatever strings the player exposes (Music's track `kind`, MediaRemote info keys).
  /// Unknown or plain AAC returns nil: no badge is better than a wrong one.
  static func classify(kind: String?, sampleRate: Double?, extras: [String] = []) -> AudioQuality? {
    let haystack = ([kind ?? ""] + extras).joined(separator: " ").lowercased()
    if haystack.contains("atmos") || haystack.contains("spatial") { return .atmos }
    guard haystack.contains("lossless") || haystack.contains("alac") else { return nil }
    if let sampleRate, sampleRate > 48_000 { return .hiRes }
    return .lossless
  }
}

/// Reads the playing track's format from Music through Apple Events (it never launches Music).
enum MusicQualityProbe {
  static func quality() -> AudioQuality? {
    guard NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").first != nil else { return nil }
    let source = """
      tell application id "com.apple.Music"
        if player state is stopped then return ""
        set t to current track
        return (kind of t) & (ASCII character 31) & (sample rate of t)
      end tell
      """
    var error: NSDictionary?
    guard let text = NSAppleScript(source: source)?.executeAndReturnError(&error).stringValue else { return nil }
    let parts = text.split(separator: "\u{1F}", omittingEmptySubsequences: false)
    guard parts.count == 2 else { return nil }
    return AudioQuality.classify(kind: String(parts[0]), sampleRate: Double(parts[1]))
  }
}

/// Resolves the badge once per song, off the main thread.
@MainActor
final class AudioQualityModel: ObservableObject {
  static let shared = AudioQualityModel()
  @Published private(set) var quality: AudioQuality?
  private var key: String?

  func sync(track: NowPlayingTrack?) {
    guard AppSettings.shared.mediaQualityBadge, let snapshot = track?.snapshot, snapshot.source == .music else {
      key = nil
      if quality != nil { quality = nil }
      return
    }
    let next = "\(snapshot.title)|\(snapshot.artist)"
    guard next != key else { return }
    key = next
    Task.detached(priority: .utility) { [weak self] in
      let value = MusicQualityProbe.quality()
      await self?.finish(value, for: next)
    }
  }

  private func finish(_ value: AudioQuality?, for next: String) {
    if key == next { quality = value }
  }
}

struct AudioQualityBadge: View {
  let quality: AudioQuality

  var body: some View {
    HStack(spacing: 3) {
      Image(systemName: quality.symbol).font(.system(size: 8, weight: .bold))
      Text(quality.title).font(.system(size: 9, weight: .semibold))
    }
    .foregroundStyle(IslandInk.secondary).fixedSize()
    .padding(.horizontal, 6).frame(height: 16)
    .background(Capsule().fill(IslandFill.raised))
    .accessibilityLabel(quality.title)
  }
}
