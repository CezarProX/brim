// DropletTile.swift
// Brim
//
// What the Widgets page needs to show a droplet, plus the shared look of droplet cards.

import SwiftUI

/// One tile on the Widgets page. Tapping it opens the droplet's island view
/// (shown inside the open island with a back chevron, about 560 x 200 pt).
struct DropletTile: Identifiable, Equatable {
  let id: DropletID
  let title: String
  let symbol: String
  let tint: Color
  let summary: String

  static let termiNotch = DropletTile(
    id: .termiNotch, title: "Termi-Notch", symbol: "terminal.fill", tint: .green,
    summary: "A quick terminal in the island")
  static let teleprompter = DropletTile(
    id: .teleprompter, title: "Teleprompter", symbol: "text.line.first.and.arrowtriangle.forward", tint: .orange,
    summary: "Scroll a script under the camera")
  static let textCapture = DropletTile(
    id: .textCapture, title: "Text Capture", symbol: "text.viewfinder", tint: .teal,
    summary: "OCR, QR codes and barcodes")
  static let dropClip = DropletTile(
    id: .dropClip, title: "DropClip", symbol: "text.cursor", tint: .purple,
    summary: "Select text, then act on it")

  static let all: [DropletTile] = [.termiNotch, .teleprompter, .textCapture, .dropClip]
}

/// Dark glass card.
struct DropletCard<Content: View>: View {
  var radius: CGFloat = IslandRadius.medium
  @ViewBuilder var content: Content

  var body: some View {
    content
      .glassCard(radius: radius)
      .overlay {
        RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(IslandFill.hairline, lineWidth: 0.75)
      }
  }
}

/// Small round icon button used in droplet toolbars.
struct DropletIconButton: View {
  let symbol: String
  let help: String
  var tint: Color = IslandInk.secondary
  /// Hit target. 28 is the island's minimum for new work; older droplet bars keep 24.
  var size: CGFloat = 24
  var action: () -> Void
  @State private var hovered = false

  var body: some View {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.system(size: size >= 28 ? 12 : 11, weight: .semibold))
        .foregroundStyle(hovered ? IslandInk.primary : tint)
        .frame(width: size, height: size)
        .background(hovered ? IslandFill.hover : IslandFill.subtle, in: Circle())
    }
    .buttonStyle(IslandPressStyle(pressedScale: 0.88))
    .onHover { hovered = $0 }
    .help(help)
    .accessibilityLabel(help)
  }
}
