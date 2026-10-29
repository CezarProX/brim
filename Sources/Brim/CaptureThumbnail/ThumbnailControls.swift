import SwiftUI

/// A round glass button for the card's corners (close, pin, edit, copy text).
struct ThumbnailIconButton: View {
  let symbol: String
  let help: String
  var isActive = false
  let action: () -> Void
  @State private var isHovered = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.system(size: 11, weight: .bold))
        .foregroundStyle(isActive ? Color.black : IslandInk.primary)
        .frame(width: 26, height: 26)
        .background(Circle().fill(isActive ? Color.white : Color.black.opacity(isHovered ? 0.72 : 0.55)))
        .background(Circle().fill(.ultraThinMaterial))
        .overlay(Circle().strokeBorder(Color.white.opacity(isActive ? 0 : 0.16), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
        .scaleEffect(isHovered ? 1.08 : 1)
        .contentShape(Circle())
    }
    .buttonStyle(ThumbnailPressStyle())
    .help(help)
    .accessibilityLabel(help)
    .onHover { hovering in withAnimation(NotchMotion.feedback(reduceMotion: reduceMotion)) { isHovered = hovering } }
  }
}

/// The centred "Copy" / "Save" pills.
struct ThumbnailPillButton: View {
  let title: String
  let action: () -> Void
  @State private var isHovered = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    Button(action: action) {
      Text(verbatim: title)
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(Color.black.opacity(0.88))
        .frame(width: 104, height: 32)
        .background(Capsule().fill(Color.white.opacity(isHovered ? 1 : 0.9)))
        .shadow(color: .black.opacity(0.28), radius: 6, y: 2)
        .contentShape(Capsule())
    }
    .buttonStyle(ThumbnailPressStyle())
    .accessibilityLabel(title)
    .onHover { hovering in withAnimation(NotchMotion.feedback(reduceMotion: reduceMotion)) { isHovered = hovering } }
  }
}

/// Presses sink a little with the app's press spring.
struct ThumbnailPressStyle: ButtonStyle {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed ? 0.92 : 1)
      .animation(NotchMotion.press(reduceMotion: reduceMotion), value: configuration.isPressed)
  }
}

/// The confirmation capsule ("Copied", "Text copied"…) that replaces the pills for a moment.
struct ThumbnailFeedbackBadge: View {
  let feedback: ThumbnailFeedback

  var body: some View {
    HStack(spacing: 7) {
      if feedback.isWorking {
        ProgressView().controlSize(.small).tint(.white)
      } else {
        Image(systemName: symbol)
          .font(.system(size: 14, weight: .bold))
          .foregroundStyle(tint)
      }
      Text(verbatim: title)
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(IslandInk.primary)
    }
    .padding(.horizontal, 16)
    .frame(height: 36)
    .background(Capsule().fill(Color.black.opacity(0.62)))
    .background(Capsule().fill(.ultraThinMaterial))
    .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5))
    .shadow(color: .black.opacity(0.22), radius: 5, y: 2)
  }

  private var title: String {
    switch feedback {
    case .working: L10n.tr("Reading text…")
    case .copied: L10n.tr("Copied")
    case .saved: L10n.tr("Saved")
    case .textCopied: L10n.tr("Text copied")
    case .noText: L10n.tr("No text found")
    case .saveFailed: L10n.tr("Couldn't save")
    }
  }

  private var symbol: String {
    switch feedback {
    case .noText: "text.badge.xmark"
    case .saveFailed: "exclamationmark.triangle.fill"
    default: "checkmark.circle.fill"
    }
  }

  private var tint: Color {
    switch feedback {
    case .noText, .saveFailed: .orange
    default: .green
    }
  }
}
