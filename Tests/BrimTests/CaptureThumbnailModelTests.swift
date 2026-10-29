import AppKit
import Foundation
import Testing

@testable import Brim

/// Records what the thumbnail asked the app to do.
@MainActor
final class FakeThumbnailServices: ThumbnailServices {
  var copies = 0
  var saves = 0
  var edits = 0
  var copiedTexts: [String] = []
  var saveSucceeds = true
  var recognizedText = "  Hello world \n"

  func copy(_ image: NSImage) { copies += 1 }
  func save(_ image: NSImage) -> Bool { saves += 1; return saveSucceeds }
  func edit(_ image: NSImage) { edits += 1 }
  func recognizeText(in image: NSImage) async -> String { recognizedText }
  func copyText(_ text: String) { copiedTexts.append(text) }
  func dragFile(for image: NSImage) -> URL? { nil }
}

/// A clock the test moves by hand.
@MainActor
final class ManualNow {
  var date = Date(timeIntervalSinceReferenceDate: 5_000)
  func advance(_ seconds: TimeInterval) { date = date.addingTimeInterval(seconds) }
}

@MainActor
@Suite("Capture thumbnail actions")
struct CaptureThumbnailModelTests {
  let services = FakeThumbnailServices()
  let time = ManualNow()

  private func makeCard(delay: TimeInterval = 6) -> (ThumbnailCardModel, () -> [ThumbnailDismissReason]) {
    let model = ThumbnailCardModel(
      id: UUID(), image: ThumbnailFixtures.image(), corner: .bottomRight, delay: delay,
      services: services, now: { [time] in time.date })
    var reasons: [ThumbnailDismissReason] = []
    model.onDismiss = { reasons.append($0) }
    return (model, { reasons })
  }

  @Test func copyCopiesAndConfirmsWithoutClosing() {
    let (card, reasons) = makeCard()
    card.perform(.copy)
    #expect(services.copies == 1)
    #expect(card.feedback == .copied)
    #expect(reasons().isEmpty)
  }

  @Test func saveConfirmsOrReportsFailure() {
    let (card, _) = makeCard()
    card.perform(.save)
    #expect(services.saves == 1)
    #expect(card.feedback == .saved)
    services.saveSucceeds = false
    card.perform(.save)
    #expect(card.feedback == .saveFailed)
  }

  @Test func editOpensTheEditorAndCloses() {
    let (card, reasons) = makeCard()
    card.perform(.edit)
    #expect(services.edits == 1)
    #expect(reasons() == [.edited])
  }

  @Test func recognizedTextIsTrimmedAndCopied() async {
    let (card, _) = makeCard()
    let task = card.perform(.recognizeText)
    #expect(card.feedback == .working)
    #expect(card.clock.isPaused)
    await task?.value
    #expect(services.copiedTexts == ["Hello world"])
    #expect(card.feedback == .textCopied)
    #expect(!card.clock.isPaused)
  }

  @Test func noTextCopiesNothing() async {
    services.recognizedText = " \n "
    let (card, _) = makeCard()
    await card.perform(.recognizeText)?.value
    #expect(services.copiedTexts.isEmpty)
    #expect(card.feedback == .noText)
  }

  @Test func closeDismissesOnce() {
    let (card, reasons) = makeCard()
    card.perform(.close)
    card.perform(.close)
    card.perform(.copy)
    #expect(reasons() == [.closed])
    #expect(services.copies == 0)
  }

  @Test func pinHoldsTheCountdownUntilUnpinned() {
    let (card, _) = makeCard()
    card.present()
    card.perform(.togglePin)
    #expect(card.isPinned && card.clock.isPaused)
    card.perform(.togglePin)
    #expect(!card.isPinned && !card.clock.isPaused)
  }

  @Test func acceptedDragOutDismissesAndARefusedOneDoesNot() {
    let (card, reasons) = makeCard()
    card.beginDragOut()
    #expect(card.isDraggingOut && card.clock.isPaused)
    card.perform(.dragEnded(accepted: false))
    #expect(!card.isDraggingOut && !card.clock.isPaused)
    #expect(reasons().isEmpty)
    card.beginDragOut()
    card.perform(.dragEnded(accepted: true))
    #expect(reasons() == [.draggedOut])
  }

  @Test func shortSwipeSpringsBackAndLongSwipeDismisses() {
    let (card, reasons) = makeCard()
    card.beginSwipe()
    card.swipeOffset = 30
    card.perform(.swipeEnded(dismiss: false))
    #expect(card.swipeOffset == 0)
    #expect(reasons().isEmpty)
    card.perform(.swipeEnded(dismiss: true))
    #expect(reasons() == [.swiped])
  }

  @Test func closesItselfAfterTheDelayUnlessHovered() {
    let (card, reasons) = makeCard(delay: 6)
    card.present()
    time.advance(3)
    card.setHovered(true)
    time.advance(60)
    card.checkExpiry()
    #expect(reasons().isEmpty)
    card.setHovered(false)
    time.advance(2.9)
    card.checkExpiry()
    #expect(reasons().isEmpty)
    time.advance(0.2)
    card.checkExpiry()
    #expect(reasons() == [.timedOut])
  }

  @Test func neverClosesWhenTheDelayIsOff() {
    let (card, reasons) = makeCard(delay: 0)
    card.present()
    time.advance(10_000)
    card.checkExpiry()
    #expect(reasons().isEmpty)
  }

  @Test func aNewImageForTheSameCaptureRestartsTheDelay() {
    let (card, reasons) = makeCard(delay: 6)
    card.present()
    time.advance(5)
    card.replaceImage(ThumbnailFixtures.image(size: CGSize(width: 100, height: 100)))
    time.advance(5)
    card.checkExpiry()
    #expect(reasons().isEmpty)
    #expect(card.image.size.width == 100)
  }

  @Test func aCaptureInProgressHoldsTheCard() {
    let (card, _) = makeCard()
    card.setSuspended(true)
    #expect(card.clock.holds == [.suspended])
    card.setSuspended(false)
    #expect(!card.clock.isPaused)
  }
}

@MainActor
@Suite("Capture thumbnail stacking", .serialized)
struct CaptureThumbnailCenterTests {
  /// Far off any real display, so the panels never appear while the tests run.
  static let bounds = CGRect(x: -30_000, y: -30_000, width: 1920, height: 1050)

  private func makeCenter(active: @escaping @MainActor () -> Bool = { false }) -> CaptureThumbnailCenter {
    let settings = AppSettings(defaults: UserDefaults(suiteName: "QS-ThumbCenter-\(UUID().uuidString)")!)
    settings.copyAfterSelection = true
    return CaptureThumbnailCenter(
      services: FakeThumbnailServices(), settings: settings, isCaptureActive: active,
      placement: { _ in ThumbnailPlacement(displayID: 7, bounds: Self.bounds) })
  }

  private func settle() async { try? await Task.sleep(for: .milliseconds(80)) }

  @Test func stacksNewestInTheCornerAndKeepsAtMostFour() async {
    let center = makeCenter()
    var ids: [UUID] = []
    for _ in 0..<5 {
      let id = UUID()
      ids.append(id)
      center.captureFinished(ThumbnailFixtures.image(), action: .copy, captureID: id, screen: nil)
      await settle()
    }
    #expect(center.visibleIDs == Array(ids.suffix(4)))
    let newest = ThumbnailLayout.panelFrame(forCard: ThumbnailLayout.cardFrame(slot: 0, corner: .bottomRight, in: Self.bounds))
    #expect(center.panelFrame(of: ids[4]) == newest)
    let oldest = center.panelFrame(of: ids[1]) ?? .zero
    #expect(oldest.minY > newest.minY)
    for id in center.visibleIDs { center.model(for: id)?.dismiss(.closed) }
    #expect(center.visibleIDs.isEmpty)
  }

  @Test func theSameCaptureUpdatesItsCard() async {
    let center = makeCenter()
    let id = UUID()
    center.captureFinished(ThumbnailFixtures.image(), action: .copy, captureID: id, screen: nil)
    await settle()
    center.captureFinished(ThumbnailFixtures.image(size: CGSize(width: 90, height: 90)), action: .save, captureID: id, screen: nil)
    await settle()
    #expect(center.visibleIDs == [id])
    #expect(center.model(for: id)?.image.size.width == 90)
    center.model(for: id)?.dismiss(.closed)
  }

  @Test func waitsForTheOverlayToClose() async {
    var overlayUp = true
    let center = makeCenter(active: { overlayUp })
    let id = UUID()
    center.captureFinished(ThumbnailFixtures.image(), action: .copy, captureID: id, screen: nil)
    await settle()
    #expect(center.visibleIDs.isEmpty)
    overlayUp = false
    try? await Task.sleep(for: .milliseconds(320))
    #expect(center.visibleIDs == [id])
    center.model(for: id)?.dismiss(.closed)
  }

  @Test func printingShowsNothing() async {
    let center = makeCenter()
    center.captureFinished(ThumbnailFixtures.image(), action: .print, captureID: UUID(), screen: nil)
    await settle()
    #expect(center.visibleIDs.isEmpty)
  }

  @Test func aNewCaptureHidesAndHoldsTheCards() async {
    var capturing = false
    let center = makeCenter(active: { capturing })
    let id = UUID()
    center.captureFinished(ThumbnailFixtures.image(), action: .copy, captureID: id, screen: nil)
    await settle()
    capturing = true
    center.captureWillBegin()
    #expect(center.model(for: id)?.clock.holds.contains(.suspended) == true)
    capturing = false
    try? await Task.sleep(for: .milliseconds(320))
    #expect(center.model(for: id)?.clock.isPaused == false)
    center.model(for: id)?.dismiss(.closed)
  }
}
