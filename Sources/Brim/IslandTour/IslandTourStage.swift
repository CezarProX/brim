import AppKit
import SwiftUI

/// The live half of the Island Tour: drives the real island for each step (opens it on the page
/// being explained, or closes it) and keeps the arrow on the thing the step talks about.
@MainActor
final class IslandTourStage {
  private let pointer = IslandTourPointerModel()
  private var panel: IslandTourPointerPanel?
  /// How the island was when the tour began, so the end can put it back.
  private var startedOpen = false
  private var startNavigation = IslandNavigation()

  private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

  func begin(on target: NotchPresentation) {
    startedOpen = target.isExpanded
    startNavigation = target.navigation
    let panel = panel ?? IslandTourPointerPanel.make()
    if self.panel == nil {
      let host = NSHostingView(rootView: IslandTourPointerView(model: pointer))
      host.sizingOptions = []
      panel.contentView = host
      self.panel = panel
    }
    panel.sharingType = AppSettings.shared.shellHideFromCapture ? .none : .readOnly
    pointer.tip = nil
    place(on: target)
    panel.orderFrontRegardless()
  }

  /// Shows `step` on the island: the page it explains (as if its tab were tapped), or the closed island.
  func demonstrate(_ step: IslandTourStep, on target: NotchPresentation) {
    let controller = NotchShelfController.shared
    switch step.demo {
    case .none:
      controller.setTourHold(step.hold, on: target)
    case .closed:
      controller.setTourHold(.none, on: target)
      controller.collapseForTour(target)
    case .page(let page):
      let navigation = target.navigation
      if navigation.page != page || navigation.openedWidget != nil || target.selectedActivity != nil {
        withAnimation(NotchMotion.layout(reduceMotion: reduceMotion)) {
          target.selectedActivity = nil
          target.navigate(to: .showing(page))
        }
      }
      // Holding opens a closed island on the next tick, already on this page.
      controller.setTourHold(step.hold, on: target)
    }
  }

  /// Moves the arrow to where `step` points on the island as it is now.
  func point(at step: IslandTourStep, on target: NotchPresentation) {
    guard let panel else { return }
    place(on: target)
    let pages = IslandPageOrder.visible(
      trayCount: FileTrayStore.shared.items.count, current: target.navigation.page,
      messageCount: NotificationHUDModel.shared.inbox.conversations.count)
    let anchor = IslandTourPointerGeometry.anchor(
      for: step.target, geometry: target.geometry, expanded: target.isExpanded, pages: pages,
      trayCount: FileTrayStore.shared.items.count)
    let frame = panel.frame
    let tip = anchor.map { CGPoint(x: ($0.point.x - frame.minX).rounded(), y: (frame.maxY - $0.point.y).rounded()) }
    if pointer.tip != tip { pointer.tip = tip }
    let swipe = anchor?.swipe ?? false
    if pointer.swipe != swipe { pointer.swipe = swipe }
  }

  /// Takes the arrow down and puts the island back: closed if it started closed, else on its first page.
  func end(on target: NotchPresentation?) {
    pointer.tip = nil
    let panel = panel
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { panel?.orderOut(nil) }
    let controller = NotchShelfController.shared
    controller.setTourHold(.none, on: nil)
    guard let target, controller.hosts(target) else { return }
    if !startedOpen {
      controller.collapseForTour(target)
    } else if target.isExpanded {
      withAnimation(NotchMotion.layout(reduceMotion: reduceMotion)) { target.navigate(to: startNavigation) }
      // Stays open until the pointer visits and leaves, as it would have without the tour.
      controller.setTourHold(.untilPointerLeaves, on: target)
    }
  }

  private func place(on target: NotchPresentation) {
    guard let panel else { return }
    let frame = IslandTourPointerGeometry.overlayFrame(for: target.geometry)
    if panel.frame != frame { panel.setFrame(frame, display: false) }
  }
}
