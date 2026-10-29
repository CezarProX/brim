import SwiftUI

/// Shared pieces of the capture-family apps (Screenshot, Recording, Remove Background, DropClip):
/// the one-line purpose under the title, and a 30 pt button with 12 pt text.
struct CaptureAppSubtitle: View {
  let text: LocalizedStringKey

  init(_ text: LocalizedStringKey) { self.text = text }

  var body: some View {
    Text(text)
      .font(.system(size: 12))
      .foregroundStyle(IslandInk.secondary)
      .lineLimit(2)
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: .infinity, alignment: .leading)
  }
}

/// Capsule button, 30 pt tall, 12 pt text. Prominent carries the tint; others sit on a raised fill.
struct CaptureAppButtonStyle: ButtonStyle {
  var prominent = false
  var tint: Color = .white

  func makeBody(configuration: Configuration) -> some View {
    CaptureAppButtonBody(configuration: configuration, prominent: prominent, tint: tint)
  }
}

private struct CaptureAppButtonBody: View {
  let configuration: ButtonStyleConfiguration
  let prominent: Bool
  let tint: Color
  @State private var hovered = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.isEnabled) private var isEnabled

  var body: some View {
    configuration.label
      .font(.system(size: 12, weight: .semibold))
      .lineLimit(1)
      .foregroundStyle(prominent ? (tint == .white ? Color.black : Color.white) : IslandInk.primary)
      .padding(.horizontal, 12)
      .frame(minWidth: 30, minHeight: 30)
      .background(fill, in: Capsule())
      .contentShape(Capsule())
      .scaleEffect(configuration.isPressed && !reduceMotion ? 0.95 : 1)
      .opacity(isEnabled ? 1 : 0.4)
      .onHover { hovered = $0 }
      .animation(NotchMotion.feedback(reduceMotion: reduceMotion), value: hovered)
      .animation(NotchMotion.press(reduceMotion: reduceMotion), value: configuration.isPressed)
  }

  private var fill: Color {
    if prominent { return tint.opacity(hovered && isEnabled ? 0.88 : 1) }
    return hovered && isEnabled ? IslandFill.hover : IslandFill.raised
  }
}
