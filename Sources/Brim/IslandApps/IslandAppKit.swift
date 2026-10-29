import SwiftUI

extension View {
  /// The soft rounded surface the apps' cards sit on.
  func islandAppCard(radius: CGFloat = IslandRadius.medium) -> some View {
    glassCard(radius: radius)
  }
}

/// A labeled 32pt action: icon and words, tinted when it is the main action or destructive.
struct IslandAppButton: View {
  enum Style { case plain, prominent(Color), destructive }

  let title: String
  let symbol: String
  var style: Style = .plain
  var height: CGFloat = 32
  let action: () -> Void
  @State private var hovered = false
  @Environment(\.isEnabled) private var isEnabled
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    Button(action: action) {
      HStack(spacing: 6) {
        Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
        Text(title).font(.system(size: 12, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.85)
      }
      .foregroundStyle(foreground)
      .padding(.horizontal, 12)
      .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
      .background(background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
      .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
      .opacity(isEnabled ? 1 : 0.4)
    }
    .buttonStyle(IslandPressStyle(pressedScale: 0.96))
    .onHover { hovered = $0 }
    .animation(NotchMotion.feedback(reduceMotion: reduceMotion), value: hovered)
    .accessibilityLabel(title)
  }

  private var foreground: Color {
    switch style {
    case .plain: IslandInk.primary
    case .prominent: .black
    case .destructive: Color(red: 1, green: 0.42, blue: 0.4)
    }
  }

  private var background: Color {
    switch style {
    case .plain: hovered ? IslandFill.hover : IslandFill.raised
    case .prominent(let tint): tint.opacity(hovered ? 0.88 : 1)
    case .destructive: Color.red.opacity(hovered ? 0.28 : 0.18)
    }
  }
}
