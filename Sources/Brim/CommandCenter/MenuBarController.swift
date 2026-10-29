import AppKit
import Combine

/// Owns what the menu-bar icon shows and does: the live-status icon, optional stats/song text, and the
/// click behaviour (Command Center popover or the short menu). AppDelegate creates the status item and
/// hands it over with the short menu.
@MainActor
final class MenuBarController: NSObject {
  static let shared = MenuBarController()

  private var item: NSStatusItem?
  private var shortMenu: NSMenu?
  private var cancellables: Set<AnyCancellable> = []
  private var tickTimer: Timer?
  private var statsAttached = false
  private var lastRefreshedStyle: MenuBarClickStyle?

  func attach(item: NSStatusItem, shortMenu: NSMenu) {
    self.item = item
    self.shortMenu = shortMenu
    item.button?.imagePosition = .imageLeading
    observe()
    applyStyle()
    refresh()
  }

  func detach() {
    cancellables.removeAll()
    tickTimer?.invalidate()
    if statsAttached { SystemStatsModel.shared.detach(); statsAttached = false }
    CommandCenterController.shared.close()
  }

  // MARK: Click handling

  private func applyStyle() {
    guard let item, let button = item.button else { return }
    let style = AppSettings.shared.menuBarClickStyle
    guard style != lastRefreshedStyle else { return }
    lastRefreshedStyle = style
    switch style {
    case .shortMenu:
      item.menu = shortMenu
      button.target = nil
      button.action = nil
    case .commandCenter:
      item.menu = nil
      button.target = self
      button.action = #selector(clicked(_:))
      button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }
  }

  @objc private func clicked(_ sender: NSStatusBarButton) {
    let isRight = NSApp.currentEvent?.type == .rightMouseUp
      || NSApp.currentEvent?.modifierFlags.contains(.control) == true
    if isRight, let item, let shortMenu {
      CommandCenterController.shared.close()
      item.menu = shortMenu
      sender.performClick(nil)
      item.menu = nil
      return
    }
    CommandCenterController.shared.toggle(anchoredTo: sender)
  }

  /// Opens the Command Center straight into edit mode (from Settings).
  func openCommandCenterForEditing() {
    guard AppSettings.shared.menuBarClickStyle == .commandCenter else { return }
    CommandCenterController.shared.show(anchoredTo: item?.button, editing: true)
  }

  // MARK: Live status

  private func observe() {
    guard cancellables.isEmpty else { return }
    let refresh: () -> Void = { [weak self] in self?.refresh() }
    NowPlayingModel.shared.$track.sink { _ in DispatchQueue.main.async(execute: refresh) }.store(in: &cancellables)
    NativeTimerModel.shared.$activeTimer.sink { _ in DispatchQueue.main.async(execute: refresh) }.store(in: &cancellables)
    ScreenRecordingModel.shared.$activeRecording.sink { _ in DispatchQueue.main.async(execute: refresh) }.store(in: &cancellables)
    CodingAgentModel.shared.$sessions.sink { _ in DispatchQueue.main.async(execute: refresh) }.store(in: &cancellables)
    let stats = SystemStatsModel.shared
    Publishers.MergeMany(stats.$cpu.map { _ in }.eraseToAnyPublisher(), stats.$memoryUsed.map { _ in }.eraseToAnyPublisher(),
                         stats.$networkDown.map { _ in }.eraseToAnyPublisher(), stats.$batteryPercent.map { _ in }.eraseToAnyPublisher())
      .sink { _ in DispatchQueue.main.async(execute: refresh) }.store(in: &cancellables)
    NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
      .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
      .sink { [weak self] _ in self?.applyStyle(); self?.refresh() }.store(in: &cancellables)
  }

  func refresh() {
    guard let button = item?.button else { return }
    let input = currentInput()
    syncStatsSampling()
    let output = MenuBarStatusPolicy.output(input)
    button.image = Self.image(for: output.icon)
    button.title = output.title.isEmpty ? "" : " " + output.title
    button.imagePosition = output.title.isEmpty ? .imageOnly : .imageLeading
    item?.length = output.title.isEmpty ? NSStatusItem.squareLength : NSStatusItem.variableLength
    syncTick(needsTick: input.timerRemaining != nil && !input.timerPaused && input.liveStatus)
  }

  private func currentInput() -> MenuBarStatusPolicy.Input {
    let settings = AppSettings.shared
    let stats = SystemStatsModel.shared
    let timer = NativeTimerModel.shared.activeTimer
    let track = NowPlayingModel.shared.track
    let sessions = CodingAgentModel.shared.sessions
    var input = MenuBarStatusPolicy.Input()
    input.liveStatus = settings.menuBarLiveStatus
    input.isRecording = ScreenRecordingModel.shared.activeRecording != nil
    input.timerRemaining = timer?.remaining()
    input.timerPaused = timer?.isPaused ?? false
    input.agentRunning = sessions.contains { if case .running = $0.state { true } else if $0.state == .thinking { true } else { false } }
    input.agentNeedsInput = sessions.contains { if case .needsInput = $0.state { true } else { false } }
    input.musicPlaying = track?.isPlaying ?? false
    input.songText = track.map { LiquidPlayerController.menuBarText(title: $0.title, artist: $0.artist, limit: 28) }
    input.showsSong = settings.menuBarShowsSong
    input.playerItemShowsSong = settings.liquidPlayerMenuBarMode && settings.liquidPlayerShowsSongInMenuBar
    input.statsReadout = MenuBarStatusPolicy.readout(
      settings.menuBarStatsReadout, cpu: stats.cpu,
      memory: Double(stats.memoryUsed) / Double(max(1, stats.memoryTotal)),
      down: stats.networkDown, up: stats.networkUp, battery: stats.batteryPercent, charging: stats.batteryCharging)
    return input
  }

  /// Sampling costs a little, so it runs only while a readout is chosen.
  private func syncStatsSampling() {
    let wanted = AppSettings.shared.menuBarStatsReadout != .off
    if wanted, !statsAttached { SystemStatsModel.shared.attach(); statsAttached = true }
    if !wanted, statsAttached { SystemStatsModel.shared.detach(); statsAttached = false }
  }

  private func syncTick(needsTick: Bool) {
    if needsTick, tickTimer == nil {
      tickTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
        MainActor.assumeIsolated { self?.refresh() }
      }
    } else if !needsTick {
      tickTimer?.invalidate()
      tickTimer = nil
    }
  }

  static func image(for icon: MenuBarStatusPolicy.Icon) -> NSImage? {
    // At rest the menu bar shows the Brim mark; live states swap in their SF Symbol.
    if icon == .idle { return AppIconRenderer.menuBarGlyph() }
    let base = NSImage(systemSymbolName: icon.symbol, accessibilityDescription: "Brim")
    guard icon.isAlert, let base else {
      base?.isTemplate = true
      return base
    }
    let config = NSImage.SymbolConfiguration(paletteColors: [.systemRed])
    let tinted = base.withSymbolConfiguration(config)
    tinted?.isTemplate = false
    return tinted
  }
}
