// IslandAppSubtitle.swift
// Brim
//
// The one-line "what is this app" caption under an opened island app's title.

import SwiftUI

struct IslandAppSubtitle: View {
  /// Pass `L10n.tr("…")` so the line is translated.
  let text: String
  init(_ text: String) { self.text = text }
  var body: some View {
    Text(text)
      .font(.system(size: 12, weight: .medium)).foregroundStyle(IslandInk.secondary)
      .lineLimit(1).minimumScaleFactor(0.9)
      .frame(maxWidth: .infinity, alignment: .leading)
  }
}

/// Capsule button at the island's app sizing: 12 pt text, 28 pt tall.
struct IslandAppPillStyle: ButtonStyle {
  var prominent = false
  var tint: Color = .white

  func makeBody(configuration: Configuration) -> some View {
    PillBody(configuration: configuration, prominent: prominent, tint: tint)
  }

  struct PillBody: View {
    let configuration: ButtonStyleConfiguration
    let prominent: Bool
    let tint: Color
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
      configuration.label
        .font(.system(size: 12, weight: .semibold)).lineLimit(1)
        .foregroundStyle(prominent ? (tint == .white ? Color.black : Color.white) : IslandInk.primary)
        .padding(.horizontal, 12).frame(height: 28)
        .background(prominent ? tint : IslandFill.raised, in: Capsule())
        .contentShape(Capsule())
        .opacity(isEnabled ? 1 : 0.4)
        .scaleEffect(configuration.isPressed && !reduceMotion ? 0.95 : 1)
        .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
  }
}
