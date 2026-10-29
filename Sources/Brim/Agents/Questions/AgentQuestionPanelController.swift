import AppKit
import Combine
import SwiftUI

/// A borderless panel under the notch that shows the head of the question queue. Separate from the
/// island's own shell so it never competes with the shelf; it takes keyboard focus only when the
/// reply field is clicked.
final class AgentQuestionPanel: NSPanel {
  init(frame: CGRect) {
    super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    isFloatingPanel = true
    level = .statusBar
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    backgroundColor = .clear
    isOpaque = false
    hasShadow = true
    hidesOnDeactivate = false
    isMovable = false
    isReleasedWhenClosed = false
    animationBehavior = .none
  }

  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }
}

@MainActor
final class AgentQuestionPanelController {
  static let shared = AgentQuestionPanelController()
  private var panel: AgentQuestionPanel?
  private var host: NSHostingView<AnyView>?
  private var shownID: UUID?
  private var watch: AnyCancellable?
  private let coordinator = AgentQuestionCoordinator.shared

  func start() {
    guard watch == nil else { return }
    watch = coordinator.$queue.receive(on: RunLoop.main).sink { [weak self] queue in self?.sync(queue) }
  }

  private func sync(_ queue: AgentQuestionQueue) {
    guard let entry = queue.current else {
      shownID = nil
      panel?.orderOut(nil)
      return
    }
    guard entry.id != shownID else { return }
    shownID = entry.id
    let view = AgentQuestionCardView(
      request: entry.request, waiting: queue.waiting,
      onChoose: { [coordinator] in coordinator.choose($0) }, onReply: { [coordinator] in coordinator.reply($0) },
      onDecide: { [coordinator] in coordinator.decide(allow: $0) },
      onJump: { [coordinator] in coordinator.jumpToTerminal() }, onClose: { [coordinator] in coordinator.dismiss() })
    let hosting = NSHostingView(rootView: AnyView(view.padding(12)))
    let size = hosting.fittingSize
    let panel = self.panel ?? AgentQuestionPanel(frame: CGRect(origin: .zero, size: size))
    self.panel = panel
    panel.contentView = hosting
    host = hosting
    panel.setFrame(frame(for: size), display: true)
    panel.orderFrontRegardless()
  }

  /// Centered under the camera housing (or the menu bar on displays without one).
  private func frame(for size: CGSize) -> CGRect {
    let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main ?? NSScreen.screens[0]
    let top = screen.safeAreaInsets.top > 0 ? screen.safeAreaInsets.top : 24
    return CGRect(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - top - size.height - 4, width: size.width, height: size.height)
  }
}
