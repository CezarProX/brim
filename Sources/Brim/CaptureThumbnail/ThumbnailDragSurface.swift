import AppKit
import SwiftUI

/// The thumbnail's pointer surface: a click edits, a flick toward the screen edge dismisses, and
/// any other drag carries the capture out as a PNG file. AppKit, because SwiftUI's `onDrag` cannot
/// report whether the drop was accepted, and a successful drop closes the card.
struct ThumbnailDragSurface: NSViewRepresentable {
  let model: ThumbnailCardModel
  let services: ThumbnailServices
  /// Gap between the card edge and the image area, for placing the drag image over the thumbnail.
  let imageInset: CGFloat

  func makeNSView(context: Context) -> ThumbnailDragView {
    let view = ThumbnailDragView()
    updateNSView(view, context: context)
    return view
  }

  func updateNSView(_ view: ThumbnailDragView, context: Context) {
    view.model = model
    view.services = services
    view.imageInset = imageInset
  }
}

@MainActor
final class ThumbnailDragView: NSView, NSDraggingSource {
  weak var model: ThumbnailCardModel?
  weak var services: ThumbnailServices?
  var imageInset: CGFloat = 0
  private var start: CGPoint?
  private var intent = ThumbnailGesture.Intent.undecided
  private var lastSample: (x: CGFloat, time: TimeInterval)?
  private var velocity: CGFloat = 0
  /// The PNG being dragged, handed to our own panels directly when their drop target misses it.
  private var draggedFile: URL?

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
  override var mouseDownCanMoveWindow: Bool { false }

  override func resetCursorRects() {
    addCursorRect(bounds, cursor: .openHand)
  }

  override func mouseDown(with event: NSEvent) {
    start = NSEvent.mouseLocation
    intent = .undecided
    velocity = 0
    lastSample = (NSEvent.mouseLocation.x, event.timestamp)
  }

  override func mouseDragged(with event: NSEvent) {
    guard let start, let model else { return }
    let point = NSEvent.mouseLocation
    let translation = CGSize(width: point.x - start.x, height: point.y - start.y)
    if intent == .undecided {
      intent = ThumbnailGesture.intent(translation: translation, corner: model.corner)
      if intent == .swipe { model.beginSwipe() }
      if intent == .fileDrag { beginFileDrag(event: event) }
    }
    guard intent == .swipe else { return }
    sampleVelocity(x: point.x, time: event.timestamp)
    model.swipeOffset = ThumbnailGesture.swipeOffset(translationX: translation.width, corner: model.corner)
  }

  override func mouseUp(with event: NSEvent) {
    defer { start = nil; intent = .undecided }
    guard let model else { return }
    switch intent {
    case .undecided: model.perform(.edit)
    case .swipe:
      let dismiss = ThumbnailGesture.swipeDismisses(offset: model.swipeOffset, velocity: velocity, corner: model.corner)
      model.perform(.swipeEnded(dismiss: dismiss))
    case .fileDrag: break
    }
  }

  private func sampleVelocity(x: CGFloat, time: TimeInterval) {
    if let lastSample, time > lastSample.time {
      let instant = (x - lastSample.x) / CGFloat(time - lastSample.time)
      velocity = velocity * 0.4 + instant * 0.6
    }
    lastSample = (x, time)
  }

  // MARK: File drag

  private func beginFileDrag(event: NSEvent) {
    guard let model, let file = services?.dragFile(for: model.image) else { return }
    let item = NSDraggingItem(pasteboardWriter: file as NSURL)
    item.setDraggingFrame(dragFrame(for: model.image), contents: model.image)
    draggedFile = file
    model.beginDragOut()
    let session = beginDraggingSession(with: [item], event: event, source: self)
    session.animatesToStartingPositionsOnCancelOrFail = true
    session.draggingFormation = .none
  }

  /// The image's aspect-fit rect inside the card, so the drag starts exactly over the thumbnail.
  private func dragFrame(for image: NSImage) -> CGRect {
    let area = bounds.insetBy(dx: imageInset, dy: imageInset)
    guard image.size.width > 0, image.size.height > 0, area.width > 0, area.height > 0 else { return bounds }
    let scale = min(area.width / image.size.width, area.height / image.size.height)
    let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
    return CGRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2, width: size.width, height: size.height)
  }

  nonisolated func draggingSession(
    _ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext
  ) -> NSDragOperation {
    context == .outsideApplication ? [.copy] : [.copy, .generic]
  }

  /// Over our own tiles or tray the capture lands there, so it shouldn't slide back first.
  nonisolated func draggingSession(_ session: NSDraggingSession, movedTo screenPoint: NSPoint) {
    MainActor.assumeIsolated {
      session.animatesToStartingPositionsOnCancelOrFail = !FloatingBasketController.shared.hasDropTarget(at: screenPoint)
    }
  }

  nonisolated func draggingSession(
    _ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation
  ) {
    MainActor.assumeIsolated {
      var accepted = !operation.isEmpty
      if !accepted, let draggedFile {
        accepted = FloatingBasketController.shared.finishDrag([draggedFile], at: screenPoint)
      } else {
        FloatingBasketController.shared.hideQuickActions()
      }
      draggedFile = nil
      model?.perform(.dragEnded(accepted: accepted))
    }
  }
}
