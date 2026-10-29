import AppKit
import Combine

/// Something the user did to a thumbnail.
enum ThumbnailAction: Equatable {
  case copy, save, edit, recognizeText, close, togglePin
  /// A file drag ended; `accepted` when another app took the file.
  case dragEnded(accepted: Bool)
  /// A swipe ended; `dismiss` when it went far or fast enough toward the edge.
  case swipeEnded(dismiss: Bool)
}

/// Short confirmation shown over the card after an action.
enum ThumbnailFeedback: Equatable {
  case working, copied, saved, textCopied, noText, saveFailed

  var isWorking: Bool { self == .working }
}

enum ThumbnailDismissReason: Equatable {
  case closed, timedOut, swiped, draggedOut, edited, evicted
}

/// One floating thumbnail: the image, its hover/pin/drag state, the auto-close countdown and the
/// routing of every action. AppKit and SwiftUI only observe it, so the behaviour is testable.
@MainActor
final class ThumbnailCardModel: ObservableObject, Identifiable {
  static let feedbackDuration: Duration = .milliseconds(1400)

  let id: UUID
  let corner: ThumbnailCorner
  @Published private(set) var image: NSImage
  /// A colour wash of the image for the card background.
  @Published private(set) var backdrop: NSImage?
  @Published private(set) var isHovered = false
  @Published private(set) var isPinned = false
  @Published private(set) var isDraggingOut = false
  @Published private(set) var feedback: ThumbnailFeedback?
  /// Horizontal offset while the card follows a swipe.
  @Published var swipeOffset: CGFloat = 0
  @Published private(set) var isPresented = false
  @Published private(set) var dismissReason: ThumbnailDismissReason?
  private(set) var clock: ThumbnailDismissClock

  /// Called once when the card should go away.
  var onDismiss: (ThumbnailDismissReason) -> Void = { _ in }
  private let services: ThumbnailServices
  private let now: () -> Date
  private var countdown: Task<Void, Never>?
  private var feedbackReset: Task<Void, Never>?

  init(
    id: UUID, image: NSImage, corner: ThumbnailCorner, delay: TimeInterval,
    services: ThumbnailServices, now: @escaping () -> Date = Date.init
  ) {
    self.id = id
    self.image = image
    backdrop = ThumbnailBackdrop.wash(for: image)
    self.corner = corner
    self.services = services
    self.now = now
    clock = ThumbnailDismissClock(delay: delay, start: now())
  }

  var isDismissed: Bool { dismissReason != nil }

  // MARK: Actions

  /// Routes an action. Async work (text recognition) comes back as a task the caller may await.
  @discardableResult
  func perform(_ action: ThumbnailAction) -> Task<Void, Never>? {
    guard !isDismissed else { return nil }
    switch action {
    case .copy:
      services.copy(image)
      show(.copied)
    case .save:
      show(services.save(image) ? .saved : .saveFailed)
    case .edit:
      services.edit(image)
      dismiss(.edited)
    case .recognizeText:
      return recognizeText()
    case .close:
      dismiss(.closed)
    case .togglePin:
      isPinned.toggle()
      updateHold(.pin, isPinned)
    case .dragEnded(let accepted):
      isDraggingOut = false
      updateHold(.drag, false)
      if accepted { dismiss(.draggedOut) }
    case .swipeEnded(let shouldDismiss):
      if shouldDismiss { dismiss(.swiped) } else { swipeOffset = 0 }
      updateHold(.drag, false)
    }
    return nil
  }

  private func recognizeText() -> Task<Void, Never>? {
    guard feedback != .working else { return nil }
    show(.working)
    return Task { [weak self] in
      guard let self else { return }
      let text = await services.recognizeText(in: image)
      guard !isDismissed else { return }
      let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
      if trimmed.isEmpty {
        show(.noText)
      } else {
        services.copyText(trimmed)
        show(.textCopied)
      }
    }
  }

  // MARK: Pointer state

  func setHovered(_ hovered: Bool) {
    guard hovered != isHovered else { return }
    isHovered = hovered
    updateHold(.hover, hovered)
  }

  func beginDragOut() {
    isDraggingOut = true
    updateHold(.drag, true)
  }

  func beginSwipe() { updateHold(.drag, true) }

  /// A new capture is being taken (the card is hidden meanwhile) or has finished.
  func setSuspended(_ suspended: Bool) { updateHold(.suspended, suspended) }

  /// The same capture produced a new image (copied, then saved): show it and start the delay over.
  func replaceImage(_ newImage: NSImage) {
    image = newImage
    backdrop = ThumbnailBackdrop.wash(for: newImage)
    clock.restart(at: now())
    scheduleCountdown()
  }

  // MARK: Lifecycle

  /// Called once the card's panel is on screen: it slides in and the countdown starts.
  func present() {
    isPresented = true
    clock.restart(at: now())
    scheduleCountdown()
  }

  func dismiss(_ reason: ThumbnailDismissReason) {
    guard !isDismissed else { return }
    dismissReason = reason
    countdown?.cancel()
    feedbackReset?.cancel()
    onDismiss(reason)
  }

  /// Checks the countdown now; the scheduled task calls this when the deadline passes.
  func checkExpiry() {
    if clock.isExpired(at: now()) { dismiss(.timedOut) }
  }

  // MARK: Private

  private func show(_ newFeedback: ThumbnailFeedback) {
    feedback = newFeedback
    updateHold(.busy, newFeedback.isWorking)
    feedbackReset?.cancel()
    guard !newFeedback.isWorking else { return }
    clock.restart(at: now())
    scheduleCountdown()
    feedbackReset = Task { [weak self] in
      try? await Task.sleep(for: Self.feedbackDuration)
      guard !Task.isCancelled, let self, self.feedback == newFeedback else { return }
      self.feedback = nil
    }
  }

  private func updateHold(_ hold: ThumbnailDismissClock.Hold, _ held: Bool) {
    clock.set(hold, held, at: now())
    scheduleCountdown()
  }

  private func scheduleCountdown() {
    countdown?.cancel()
    guard isPresented, !isDismissed, let deadline = clock.deadline else { return }
    let wait = max(0, deadline.timeIntervalSince(now()))
    countdown = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(Int(wait * 1000) + 20))
      guard !Task.isCancelled else { return }
      self?.checkExpiry()
    }
  }
}
