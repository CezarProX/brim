import SwiftUI

/// A filled capsule button with dark text on a bright tint, the one primary action of a screen.
struct AppPrimaryButtonStyle: ButtonStyle {
  var tint: Color
  @Environment(\.isEnabled) private var isEnabled
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 13, weight: .semibold))
      .foregroundStyle(Color.black.opacity(0.88))
      .padding(.horizontal, 16).frame(minHeight: 32)
      .background(tint.opacity(configuration.isPressed ? 0.8 : 1), in: Capsule())
      .contentShape(Capsule())
      .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
      .opacity(isEnabled ? 1 : 0.4)
  }
}

/// A quiet capsule button for the secondary action beside a primary one.
struct AppSecondaryButtonStyle: ButtonStyle {
  @Environment(\.isEnabled) private var isEnabled
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 13, weight: .medium))
      .foregroundStyle(IslandInk.primary)
      .padding(.horizontal, 14).frame(minHeight: 32)
      .background(configuration.isPressed ? IslandFill.hover : IslandFill.raised, in: Capsule())
      .contentShape(Capsule())
      .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
      .opacity(isEnabled ? 1 : 0.4)
  }
}

/// A round icon button, 28 pt, for the tools in an editor's header.
struct AppIconButton: View {
  let symbol: String
  let label: String
  var tint: Color = IslandInk.secondary
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: symbol).font(.system(size: 12, weight: .medium)).foregroundStyle(tint)
        .frame(width: 28, height: 28).background(IslandFill.subtle, in: Circle())
        .contentShape(Circle())
    }
    .buttonStyle(IslandPressStyle()).help(label).accessibilityLabel(label)
  }
}

/// First-run and empty states for the apps: an icon, one sentence on what this is, and one clear
/// button for what to do next. An optional second button and a footnote sit under it.
struct AppEmptyState: View {
  let symbol: String
  let tint: Color
  let title: String
  let message: String
  var primaryTitle: String?
  var primaryAction: (() -> Void)?
  var secondaryTitle: String?
  var secondaryAction: (() -> Void)?
  var footnote: String?

  var body: some View {
    VStack(spacing: 6) {
      Spacer(minLength: 0)
      Image(systemName: symbol).font(.system(size: 26, weight: .regular)).foregroundStyle(tint)
        .frame(width: 48, height: 48).background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
      Text(title).font(IslandFont.title).foregroundStyle(IslandInk.primary).padding(.top, 4)
      Text(message).font(IslandFont.body).foregroundStyle(IslandInk.secondary)
        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true).frame(maxWidth: 360)
      if primaryTitle != nil || secondaryTitle != nil {
        HStack(spacing: 8) {
          if let primaryTitle, let primaryAction {
            Button(primaryTitle, action: primaryAction).buttonStyle(AppPrimaryButtonStyle(tint: tint))
          }
          if let secondaryTitle, let secondaryAction {
            Button(secondaryTitle, action: secondaryAction).buttonStyle(AppSecondaryButtonStyle())
          }
        }
        .padding(.top, 6)
      }
      if let footnote {
        Text(footnote).font(IslandFont.body).foregroundStyle(IslandInk.tertiary)
          .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true).frame(maxWidth: 380)
      }
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
