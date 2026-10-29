import SwiftUI

/// A red "muted" capsule.
struct MutedBadge: View {
  var body: some View {
    HStack(spacing: 4) {
      Image(systemName: "mic.slash.fill").font(.system(size: 9, weight: .bold))
      Text("Muted").font(IslandFont.caption.weight(.semibold))
    }
    .foregroundStyle(Color.red)
    .padding(.horizontal, 8).frame(height: 22)
    .background(Color.red.opacity(0.16), in: Capsule())
    .transition(.scale.combined(with: .opacity))
  }
}

/// Compact-wing glyph for a call: the phone, or a red muted microphone while either the call app or the system
/// microphone is muted.
struct CallCompactGlyph: View {
  @ObservedObject private var calls = CallActivityModel.shared
  @ObservedObject private var microphones = MicrophoneMuteController.shared
  /// Previews and tests pin this instead of reading the live models.
  var mutedOverride: Bool?

  private var muted: Bool { mutedOverride ?? (calls.activeCall?.isMuted == true || microphones.isMuted) }

  var body: some View {
    Image(systemName: muted ? "mic.slash.fill" : "phone.fill")
      .font(.system(size: 15)).foregroundStyle(muted ? Color.red : Color.green)
      .contentTransition(.symbolEffect(.replace))
      .accessibilityLabel(muted ? "Call, microphone muted" : "Call")
  }
}
