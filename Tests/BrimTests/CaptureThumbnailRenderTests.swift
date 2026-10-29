import AppKit
import SwiftUI
import Testing

@testable import Brim

/// Renders the floating capture card to .renders/ so its states can be looked at.
@MainActor
@Suite("Capture thumbnail renders", .serialized)
struct CaptureThumbnailRenderTests {
  private static let panel = ThumbnailLayout.panelFrame(forCard: CGRect(origin: .zero, size: ThumbnailLayout.cardSize)).size

  /// A desktop-like backdrop, so the glass card is judged where it will really sit.
  private struct Desktop<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
      ZStack(alignment: .bottomTrailing) {
        LinearGradient(
          colors: [Color(red: 0.16, green: 0.22, blue: 0.52), Color(red: 0.42, green: 0.27, blue: 0.62), Color(red: 0.93, green: 0.55, blue: 0.45)],
          startPoint: .topLeading, endPoint: .bottomTrailing)
        content
      }
    }
  }

  private func card(_ size: CGSize = CGSize(width: 640, height: 400), configure: (ThumbnailCardModel) -> Void = { _ in }) -> some View {
    let services = FakeThumbnailServices()
    let model = ThumbnailCardModel(
      id: UUID(), image: ThumbnailFixtures.image(size: size), corner: .bottomRight, delay: 0, services: services)
    model.present()
    configure(model)
    return ThumbnailCardView(model: model, services: services)
  }

  @Test func idle() async throws {
    try await DropletRender.png(Desktop { card() }, size: Self.panel, name: "capture-thumbnail-idle.png", background: .clear)
  }

  @Test func hoveredWithControls() async throws {
    let view = Desktop { card { $0.setHovered(true) } }
    try await DropletRender.png(view, size: Self.panel, name: "capture-thumbnail-hover.png", background: .clear)
  }

  @Test func copiedConfirmation() async throws {
    let view = Desktop { card { $0.setHovered(true); $0.perform(.copy) } }
    try await DropletRender.png(view, size: Self.panel, name: "capture-thumbnail-copied.png", background: .clear)
  }

  @Test func pinnedTallCapture() async throws {
    let view = Desktop { card(CGSize(width: 300, height: 520)) { $0.perform(.togglePin) } }
    try await DropletRender.png(view, size: Self.panel, name: "capture-thumbnail-pinned.png", background: .clear)
  }

  /// Three captures in the bottom-right corner, newest nearest the corner, as on screen.
  @Test func stackedThree() async throws {
    let screen = CGRect(x: 0, y: 0, width: 520, height: 3 * (ThumbnailLayout.cardSize.height + ThumbnailLayout.spacing) + 60)
    let sizes = [CGSize(width: 640, height: 400), CGSize(width: 420, height: 420), CGSize(width: 900, height: 300)]
    let view = Desktop {
      ZStack(alignment: .topLeading) {
        ForEach(Array(sizes.enumerated()), id: \.offset) { slot, size in
          let frame = ThumbnailLayout.panelFrame(
            forCard: ThumbnailLayout.cardFrame(slot: slot, corner: .bottomRight, in: screen))
          card(size)
            .frame(width: frame.width, height: frame.height)
            .offset(x: frame.minX, y: screen.height - frame.maxY)
        }
      }
      .frame(width: screen.width, height: screen.height, alignment: .topLeading)
    }
    try await DropletRender.png(view, size: screen.size, name: "capture-thumbnail-stack.png", background: .clear)
  }
}
