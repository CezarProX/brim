import AppKit
import SwiftUI

/// Owns the floating capture thumbnails: one panel per capture in the corner of the screen it was
/// taken on, stacked newest-nearest-the-corner, at most as many as fit (four at most).
@MainActor
final class CaptureThumbnailCenter {
  static let shared = CaptureThumbnailCenter()

  private struct Card {
    let model: ThumbnailCardModel
    let panel: ThumbnailPanel
    var displayID: CGDirectDisplayID
  }

  private struct Pending {
    let image: NSImage
    let id: UUID
    let displayID: CGDirectDisplayID?
  }

  /// On screen, oldest first.
  private var cards: [Card] = []
  private var pending: [Pending] = []
  private var isSuspended = false
  private var waiter: Task<Void, Never>?
  private let services: ThumbnailServices
  private let settings: AppSettings
  private let isCaptureActive: @MainActor () -> Bool
  private let placement: @MainActor (CGDirectDisplayID?) -> ThumbnailPlacement?

  /// Tests inject fakes; the app uses the live services, the capture coordinator and real screens.
  init(
    services: ThumbnailServices? = nil,
    settings: AppSettings = .shared,
    isCaptureActive: (@MainActor () -> Bool)? = nil,
    placement: (@MainActor (CGDirectDisplayID?) -> ThumbnailPlacement?)? = nil
  ) {
    self.services = services ?? LiveThumbnailServices.shared
    self.settings = settings
    self.isCaptureActive = isCaptureActive ?? { CaptureCoordinator.shared.state != .idle }
    self.placement = placement ?? { ThumbnailPlacement.resolve($0) }
    NotificationCenter.default.addObserver(
      forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.relayout(animated: false) }
    }
  }

  // MARK: Entry points

  /// The capture flow's hand-off: a finished capture and the action that finished it.
  func captureFinished(_ image: NSImage, action: OverlayAction, captureID: UUID, screen: NSScreen?) {
    let enabled = settings.captureThumbnailEnabled
    guard ThumbnailPolicy.presents(action, copyAfterSelection: settings.copyAfterSelection, enabled: enabled) else { return }
    show(image, id: captureID, displayID: screen?.thumbnailDisplayID)
  }

  /// Shows a thumbnail once no capture overlay is up. The same capture id updates its card.
  func show(_ image: NSImage, id: UUID, displayID: CGDirectDisplayID?) {
    if let card = cards.first(where: { $0.model.id == id }), !card.model.isDismissed {
      card.model.replaceImage(image)
      return
    }
    pending.removeAll { $0.id == id }
    pending.append(Pending(image: image, id: id, displayID: displayID))
    flushWhenIdle()
  }

  /// A new capture is starting: hide the thumbnails so the frozen screen does not include them.
  func captureWillBegin() {
    guard !cards.isEmpty else { return }
    isSuspended = true
    for card in cards {
      card.panel.orderOut(nil)
      card.model.setSuspended(true)
    }
    flushWhenIdle()
  }

  /// Settings changed: switching off, or moving the corner, closes what is showing.
  func settingsChanged() {
    let corner = settings.captureThumbnailCorner
    for card in cards where !settings.captureThumbnailEnabled || card.model.corner != corner {
      card.model.dismiss(.closed)
    }
  }

  // MARK: Inspection (tests)

  var visibleIDs: [UUID] { cards.map(\.model.id) }
  func panelFrame(of id: UUID) -> CGRect? { cards.first { $0.model.id == id }?.panel.frame }
  func model(for id: UUID) -> ThumbnailCardModel? { cards.first { $0.model.id == id }?.model }

  // MARK: Presenting

  private func flushWhenIdle() {
    guard waiter == nil else { return }
    waiter = Task { [weak self] in
      // The capture flow tears its overlay down right after handing the image over.
      await Task.yield()
      while !Task.isCancelled, self?.isCaptureActive() == true {
        try? await Task.sleep(for: .milliseconds(200))
      }
      self?.waiter = nil
      self?.resume()
    }
  }

  private func resume() {
    if isSuspended {
      isSuspended = false
      for card in cards {
        card.panel.orderFrontRegardless()
        card.model.setSuspended(false)
      }
    }
    let queued = pending
    pending = []
    queued.forEach(insert)
  }

  private func insert(_ item: Pending) {
    guard let place = placement(item.displayID) else { return }
    let model = ThumbnailCardModel(
      id: item.id, image: item.image, corner: settings.captureThumbnailCorner,
      delay: settings.captureThumbnailAutoClose, services: services)
    model.onDismiss = { [weak self] _ in self?.remove(item.id) }
    let slot = ThumbnailLayout.cardFrame(slot: 0, corner: model.corner, in: place.bounds)
    let panel = ThumbnailPanel(frame: ThumbnailLayout.panelFrame(forCard: slot))
    panel.contentView = ThumbnailHostingView(rootView: ThumbnailCardView(model: model, services: services))
    cards.append(Card(model: model, panel: panel, displayID: place.displayID))
    evictOverflow(on: place)
    relayout(animated: true)
    panel.orderFrontRegardless()
    // One frame off screen first, so the slide-in has somewhere to come from.
    DispatchQueue.main.async { model.present() }
  }

  private func evictOverflow(on place: ThumbnailPlacement) {
    let onScreen = cards.filter { $0.displayID == place.displayID }
    let pinned = Set(onScreen.filter(\.model.isPinned).map(\.model.id))
    let evicted = ThumbnailLayout.evictions(
      oldestFirst: onScreen.map(\.model.id), pinned: pinned, capacity: ThumbnailLayout.capacity(in: place.bounds))
    for id in evicted { model(for: id)?.dismiss(.evicted) }
  }

  private func remove(_ id: UUID) {
    guard let card = cards.first(where: { $0.model.id == id }) else { return }
    cards.removeAll { $0.model.id == id }
    relayout(animated: true)
    Task {
      try? await Task.sleep(for: .milliseconds(450))
      card.panel.orderOut(nil)
      card.panel.contentView = nil
    }
  }

  // MARK: Layout

  private func relayout(animated: Bool) {
    for index in cards.indices {
      if let place = placement(cards[index].displayID) { cards[index].displayID = place.displayID }
    }
    for displayID in Set(cards.map(\.displayID)) {
      guard let place = placement(displayID) else { continue }
      let column = cards.filter { $0.displayID == displayID }
      let slots = ThumbnailLayout.slots(oldestFirst: column.map(\.model.id))
      for card in column {
        let frame = ThumbnailLayout.cardFrame(slot: slots[card.model.id] ?? 0, corner: card.model.corner, in: place.bounds)
        move(card.panel, to: ThumbnailLayout.panelFrame(forCard: frame), animated: animated)
      }
    }
  }

  private func move(_ panel: ThumbnailPanel, to frame: CGRect, animated: Bool) {
    guard panel.frame != frame else { return }
    let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    guard animated, !reduceMotion, panel.isVisible else {
      panel.setFrame(frame, display: true)
      return
    }
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.42 * settings.shellAnimationSpeed.durationScale
      // An ease-out with a soft landing, close to the island's layout spring.
      context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
      panel.animator().setFrame(frame, display: true)
    }
  }
}
