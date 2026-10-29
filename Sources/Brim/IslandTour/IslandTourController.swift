import AppKit
import Combine
import SwiftUI
import os

/// Runs the Island Tour: a coach card under the real island and an arrow pointing at what each step
/// explains. Every step shows itself on the island (Next opens the page it talks about), and a step
/// the user does by hand moves the tour on too. It starts once by itself (after the
/// introduction, or a few seconds after launch for people who saw the introduction before) and
/// again whenever Settings, the menu bar menu or the island's options ask for it.
@MainActor
final class IslandTourController {
  static let shared = IslandTourController()
  private static let log = Logger(subsystem: "io.github.cezarprox.brim", category: "island-tour")

  private let model = IslandTourCardModel()
  private let stage = IslandTourStage()
  private var session = IslandTourSession()
  private var panel: IslandTourPanel?
  private var host: NSView?
  /// Where the card window is headed; compared instead of `panel.frame`, which moves mid-animation.
  private var targetFrame: CGRect?
  private weak var presentation: NotchPresentation?
  private var observers: Set<AnyCancellable> = []
  private var screenObserver: NSObjectProtocol?
  private var pendingStart: DispatchWorkItem?

  var isRunning: Bool { panel != nil }

  private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

  // MARK: Starting

  /// Starts the tour after `delay` if it has never run and the island is on.
  func startIfNeeded(after delay: TimeInterval) {
    guard Self.mayStartByItself() else { return }
    pendingStart?.cancel()
    let work = DispatchWorkItem { [weak self] in
      MainActor.assumeIsolated { self?.startByItself() }
    }
    pendingStart = work
    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
  }

  private static func mayStartByItself() -> Bool {
    let settings = AppSettings.shared
    return IslandTourPolicy.startsAutomatically(
      islandEnabled: settings.notchShelfEnabled, introductionDone: settings.onboardingCompleted,
      tourDone: settings.islandTourCompleted)
  }

  private func startByItself() {
    pendingStart = nil
    guard Self.mayStartByItself(), !isRunning,
          let target = NotchShelfController.shared.tourPresentation(requireVisible: true) else {
      Self.log.info("Island Tour not started automatically: island off, hidden or tour already running")
      return
    }
    begin(on: target)
  }

  /// From Settings, the menu bar menu or the island's options: starts over, or explains why it can't.
  func start() {
    pendingStart?.cancel()
    pendingStart = nil
    guard AppSettings.shared.notchShelfEnabled,
          let target = NotchShelfController.shared.tourPresentation(requireVisible: false) else {
      explainIslandOff()
      return
    }
    if isRunning { tearDown() }
    begin(on: target)
  }

  private func begin(on target: NotchPresentation) {
    Self.log.info("Island Tour started")
    session = IslandTourSession()
    presentation = target
    model.step = session.step
    model.context = context(for: target)
    stage.begin(on: target)
    showPanel()
    observe(target)
    // The first look: an island that is already open passes "Open the island" straight away.
    session.observe(snapshot(of: target))
    applyStep()
  }

  private func explainIslandOff() {
    let alert = NSAlert()
    alert.messageText = L10n.tr("The island is turned off")
    alert.informativeText = L10n.tr("Turn on “Enable Brim at the notch” in Settings → General, then take the tour.")
    alert.addButton(withTitle: L10n.tr("Open Settings"))
    alert.addButton(withTitle: L10n.tr("OK"))
    NSApp.activate(ignoringOtherApps: true)
    if alert.runModal() == .alertFirstButtonReturn {
      SettingsWindowController.shared.show(page: .general, anchor: "general.notch")
    }
  }

  // MARK: Following the island

  private func observe(_ target: NotchPresentation) {
    let resync: (Any) -> Void = { [weak self] _ in MainActor.assumeIsolated { self?.sync() } }
    observers = [
      // objectWillChange fires before the change; hopping a turn of the run loop reads the new state.
      target.objectWillChange.receive(on: RunLoop.main).sink(receiveValue: resync),
    ]
    if screenObserver == nil {
      screenObserver = NotificationCenter.default.addObserver(
        forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
      ) { [weak self] _ in
        // The island controller rebuilds its panels on the same notification; follow a beat later.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { MainActor.assumeIsolated { self?.sync() } }
      }
    }
  }

  /// Reads the island, moves the tour on when the user did the step, and keeps the card in place.
  private func sync() {
    guard session.isRunning, let target = presentation else { return }
    guard NotchShelfController.shared.hosts(target) else { retarget(); return }
    let before = session.step
    if session.observe(snapshot(of: target)) {
      Self.log.info("Island Tour step \(before.rawValue + 1) done by the user")
      ShellHaptics.tick()
    }
    let context = context(for: target)
    if model.context != context { model.context = context; resizePanel() }
    if session.step != before {
      applyStep()
    } else {
      positionPanel(animated: true)
      stage.point(at: session.step, on: target)
    }
  }

  private func snapshot(of target: NotchPresentation) -> IslandTourSnapshot {
    IslandTourSnapshot(expanded: target.isExpanded, page: target.navigation.page)
  }

  /// Displays changed and the island was rebuilt: carry on with the new one.
  private func retarget() {
    guard let next = NotchShelfController.shared.tourPresentation(requireVisible: false) else { finish(); return }
    presentation = next
    stage.begin(on: next)
    observe(next)
    applyStep()
  }

  private func context(for target: NotchPresentation) -> IslandTourContext {
    IslandTourContext(
      hasTrack: NowPlayingModel.shared.track != nil, floating: target.geometry.isFloating,
      opensOnHover: AppSettings.shared.shellOpensOnHover)
  }

  // MARK: Buttons

  private func next() {
    session.next()
    session.isRunning ? applyStep() : finish()
  }

  private func back() {
    session.back()
    applyStep()
  }

  private func skip() {
    session.skip()
    finish()
  }

  /// The step changed: show it on the island, point the arrow at it, and show the new copy.
  /// What the tour itself changed becomes the baseline, so only the user's own moves complete steps.
  private func applyStep() {
    guard let target = presentation else { return }
    let step = session.step
    stage.demonstrate(step, on: target)
    session.rebase(snapshot(of: target))
    withAnimation(NotchMotion.layout(reduceMotion: reduceMotion)) { model.step = step }
    resizePanel()
    stage.point(at: step, on: target)
    announce(step)
  }

  private func announce(_ step: IslandTourStep) {
    guard let panel else { return }
    let text = ([step.title] + step.lines(model.context)).map { L10n.tr($0) }.joined(separator: ". ")
    NSAccessibility.post(element: panel, notification: .announcementRequested,
                         userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])
  }

  private func finish() {
    if let outcome = session.outcome {
      IslandTourPolicy.record(outcome, in: .shared)
      Self.log.info("Island Tour \(outcome == .finished ? "finished" : "skipped", privacy: .public)")
    } else {
      IslandTourPolicy.record(.skipped, in: .shared)
    }
    tearDown()
  }

  private func tearDown() {
    observers.removeAll()
    if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
    screenObserver = nil
    stage.end(on: presentation)
    NotchShelfController.shared.tourCardFrame = nil
    presentation = nil
    guard let panel else { return }
    self.panel = nil
    host = nil
    targetFrame = nil
    withAnimation(NotchMotion.expansion(false, reduceMotion: reduceMotion)) { model.visible = false }
    DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0.05 : 0.35)) { panel.orderOut(nil) }
  }

  // MARK: Card window

  private func showPanel() {
    let panel = IslandTourPanel.make()
    let card = IslandTourCard(
      model: model, back: { [weak self] in self?.back() }, next: { [weak self] in self?.next() },
      skip: { [weak self] in self?.skip() })
    let host = FirstClickHostingView(rootView: card)
    panel.contentView = host
    panel.sharingType = AppSettings.shared.shellHideFromCapture ? .none : .readOnly
    self.panel = panel
    self.host = host
    model.visible = false
    resizePanel(animated: false)
    panel.orderFrontRegardless()
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      withAnimation(NotchMotion.expansion(true, reduceMotion: self.reduceMotion)) { self.model.visible = true }
    }
  }

  /// Fits the window to the card's height for the current copy, then places it.
  private func resizePanel(animated: Bool = true) {
    guard let host else { return }
    host.layoutSubtreeIfNeeded()
    let size = host.fittingSize
    positionPanel(size: size, animated: animated)
  }

  private func positionPanel(size: CGSize? = nil, animated: Bool) {
    guard let panel, let target = presentation else { return }
    let frame = IslandTourLayout.panelFrame(
      geometry: target.geometry, expanded: target.isExpanded, size: size ?? panel.frame.size)
    NotchShelfController.shared.tourCardFrame = frame.insetBy(dx: IslandTourLayout.shadowMargin, dy: IslandTourLayout.shadowMargin)
    guard frame != targetFrame else { return }
    let first = targetFrame == nil
    targetFrame = frame
    guard animated, !first, !reduceMotion else {
      panel.setFrame(frame, display: true)
      return
    }
    NSAnimationContext.runAnimationGroup { context in
      // An ease-out close to the shell's open spring; AppKit window frames can't run SwiftUI springs.
      context.duration = 0.42 * AppSettings.shared.shellAnimationSpeed.durationScale
      context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
      panel.animator().setFrame(frame, display: true)
    }
  }
}
