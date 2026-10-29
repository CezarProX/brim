import AppKit
import SwiftUI
import Testing

@testable import Brim

/// Clicks delivered to a real, non-key `ThumbnailPanel` through `sendEvent`, the way AppKit routes
/// them: the hover controls must win over the drag surface, and a bare click on the image edits.
@MainActor
@Suite("Capture thumbnail clicks", .serialized)
struct CaptureThumbnailClickTests {
  @MainActor struct Rig {
    let panel: ThumbnailPanel
    let model: ThumbnailCardModel
    let services: FakeThumbnailServices
    var reasons: () -> [ThumbnailDismissReason]

    /// A point in card coordinates (origin top-left, like SwiftUI) to window coordinates.
    func windowPoint(cardX: CGFloat, cardY: CGFloat) -> CGPoint {
      let inset = ThumbnailLayout.shadowInset
      return CGPoint(x: inset + cardX, y: panel.frame.height - inset - cardY)
    }

    func click(cardX: CGFloat, cardY: CGFloat) async throws {
      let location = windowPoint(cardX: cardX, cardY: cardY)
      for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
        let event = try #require(NSEvent.mouseEvent(
          with: type, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
          windowNumber: panel.windowNumber, context: nil, eventNumber: 0, clickCount: 1,
          pressure: type == .leftMouseDown ? 1 : 0))
        panel.sendEvent(event)
        try await Task.sleep(for: .milliseconds(40))
      }
      try await Task.sleep(for: .milliseconds(150))
    }

    func close() {
      panel.orderOut(nil)
      panel.contentView = nil
    }
  }

  private func makeRig() async throws -> Rig {
    let services = FakeThumbnailServices()
    let model = ThumbnailCardModel(
      id: UUID(), image: ThumbnailFixtures.image(size: CGSize(width: 640, height: 400)), corner: .bottomRight,
      delay: 0, services: services)
    var reasons: [ThumbnailDismissReason] = []
    model.onDismiss = { reasons.append($0) }
    let card = CGRect(origin: CGPoint(x: -30_000, y: -30_000), size: ThumbnailLayout.cardSize)
    let panel = ThumbnailPanel(frame: ThumbnailLayout.panelFrame(forCard: card))
    panel.contentView = ThumbnailHostingView(rootView: ThumbnailCardView(model: model, services: services))
    panel.orderFrontRegardless()
    model.present()
    model.setHovered(true)
    try await Task.sleep(for: .milliseconds(700))
    return Rig(panel: panel, model: model, services: services, reasons: { reasons })
  }

  private var size: CGSize { ThumbnailLayout.cardSize }

  @Test func copyPillCopies() async throws {
    let rig = try await makeRig()
    defer { rig.close() }
    try await rig.click(cardX: size.width / 2, cardY: size.height / 2 - 20)
    #expect(rig.services.copies == 1)
    #expect(rig.services.edits == 0)
  }

  @Test func savePillSaves() async throws {
    let rig = try await makeRig()
    defer { rig.close() }
    try await rig.click(cardX: size.width / 2, cardY: size.height / 2 + 20)
    #expect(rig.services.saves == 1)
  }

  @Test func closeButtonCloses() async throws {
    let rig = try await makeRig()
    defer { rig.close() }
    try await rig.click(cardX: 10 + 13, cardY: 10 + 13)
    #expect(rig.reasons() == [.closed])
  }

  @Test func pinButtonPins() async throws {
    let rig = try await makeRig()
    defer { rig.close() }
    try await rig.click(cardX: size.width - 23, cardY: 23)
    #expect(rig.model.isPinned)
  }

  @Test func clickingTheImageEdits() async throws {
    let rig = try await makeRig()
    defer { rig.close() }
    try await rig.click(cardX: 70, cardY: size.height / 2)
    #expect(rig.services.edits == 1)
    #expect(rig.reasons() == [.edited])
  }
}
