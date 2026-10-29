import SwiftUI

/// A tiny "L" beside the title when synced lyrics exist for the playing song.
struct LyricsBadge: View {
  @ObservedObject var lyrics: LyricsModel = .shared
  var size: CGFloat = 13

  /// Pure rule: shown only when the feature is on and lyrics were found for this song.
  static func isVisible(enabled: Bool, state: LyricsModel.State) -> Bool {
    if enabled, case .ready = state { return true } else { return false }
  }

  var body: some View {
    if Self.isVisible(enabled: AppSettings.shared.lyricsEnabled, state: lyrics.state) {
      Text("L")
        .font(.system(size: size * 0.72, weight: .heavy, design: .rounded))
        .foregroundStyle(IslandInk.secondary)
        .frame(width: size + 2, height: size)
        .background(IslandFill.raised, in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
        .transition(.opacity.combined(with: .scale(scale: 0.8)))
        .help("Synced lyrics available")
        .accessibilityLabel("Synced lyrics available")
    }
  }
}
