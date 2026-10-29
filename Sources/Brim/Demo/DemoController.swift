import AppKit
import SwiftUI
import os

/// Scripted demo for filming the launch video. Only runs when Brim is launched with `--demo`;
/// then it listens for `io.github.cezarprox.brim.demo` distributed notifications whose `command` is a
/// `DemoCommand` line, and puts the real island into that state (pages, flashes, Tray, Basket, Ring)
/// without a pointer hovering it. `marketing/launch-video/record/film-demo.sh` drives it.
@MainActor
final class DemoController {
  static let shared = DemoController()
  static let notification = Notification.Name("io.github.cezarprox.brim.demo")
  static var isRequested: Bool { CommandLine.arguments.contains("--demo") }
  private static let log = Logger(subsystem: "io.github.cezarprox.brim", category: "demo")

  private var observer: NSObjectProtocol?
  private var savedHideOnFullscreen: Bool?
  /// The user's own Tray, hidden while filming so only sample files show.
  private var savedTray: [FileTrayItem]?
  private var addedTrayItems: Set<UUID> = []
  /// Settings that would leak or broadcast the sample song (Discord status, live audio bars).
  private var savedMediaSettings: (discord: Bool, visualizer: Bool)?
  private var savedPinnedCountdown: PinnedCountdown??
  /// The user's real chats on the Messages page, hidden while filming.
  private var savedInbox: NotificationInbox?
  private var savedHUDTarget: HUDDisplayTarget?
  private var typing: Task<Void, Never>?
  private var thumbnailID: UUID?
  private var editor: ShelfEditorWindowController?
  private var drawing: Task<Void, Never>?

  /// The Clipboard page reads these instead of the real history and screenshots while filming.
  static private(set) var clipboardOverride: ClipboardStore?
  static private(set) var shelfOverride: ShelfStore?

  private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
  private var shelf: NotchShelfController { .shared }

  func start() {
    guard Self.isRequested, observer == nil else { return }
    observer = DistributedNotificationCenter.default().addObserver(
      forName: Self.notification, object: nil, queue: .main
    ) { note in
      let line = note.userInfo?["command"] as? String ?? ""
      MainActor.assumeIsolated { DemoController.shared.handle(line) }
    }
    // Ready before the first command arrives (a `prepare` sent too early would be lost), but after
    // launch has started the real sources, which `prepare` swaps for sample data.
    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.prepare() }
    Self.log.notice("demo mode listening")
  }

  func stop() {
    if let observer { DistributedNotificationCenter.default().removeObserver(observer) }
    observer = nil
    finish()
  }

  private func handle(_ line: String) {
    guard let command = DemoCommand.parse(line) else {
      Self.log.error("ignored demo command: \(line, privacy: .public)")
      return
    }
    Self.log.debug("demo: \(line, privacy: .public)")
    run(command)
  }

  private func run(_ command: DemoCommand) {
    switch command {
    case .prepare: prepare()
    case .finish: finish()
    case .open(let page): show(.showing(page))
    case .widget(let tile): show(.opening(tile))
    case .close: close()
    case .customize(let on): customize(on)
    case .pill(let on): usePill(on)
    case .flash(let flash): show(flash)
    case .trayAdd(let urls): addToTray(urls)
    case .trayClear:
      FileTrayStore.shared.remove(addedTrayItems)
      addedTrayItems = []
    case .basket(let point, let urls): FloatingBasketController.shared.receive(urls, near: point)
    case .basketClose: FloatingBasketController.shared.closeAll()
    case .quickActions(let point): FloatingBasketController.shared.showQuickActions(near: point)
    case .quickActionsClose: FloatingBasketController.shared.hideQuickActions()
    case .message(let sender, let body):
      NotificationHUDModel.shared.presentForDemo(
        NotificationContent(bundleID: NotificationApps.messages, appName: "Messages", title: sender, body: body))
      // The card reads in full only with the island open, as when the pointer rests on it.
      if let target { shelf.setTourHold(.open, on: target) }
    case .type(let text): type(text)
    case .send:
      typing?.cancel()
      let model = NotificationHUDModel.shared
      guard let item = model.current else { return }
      model.reply(model.replies.drafts[item.id] ?? "", to: item)
    case .ring(let point): RingMenuController.shared.show(at: point)
    case .ringClose: RingMenuController.shared.close()
    case .thumbnail(let url): showThumbnail(of: url)
    case .thumbnailHover(let on):
      if let thumbnailID { CaptureThumbnailCenter.shared.model(for: thumbnailID)?.setHovered(on) }
    case .thumbnailClose: closeThumbnail()
    case .editorOpen(let url): openEditor(on: url)
    case .editorClose: closeEditor()
    case .mark(let mark): draw(mark)
    }
  }

  private static var trayBackupURL: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Brim/demo-tray-backup.json")
  }

  private static func readTrayBackup() -> [FileTrayItem]? {
    guard let data = try? Data(contentsOf: trayBackupURL) else { return nil }
    return try? JSONDecoder().decode([FileTrayItem].self, from: data)
  }

  private static func writeTrayBackup(_ items: [FileTrayItem]) {
    do {
      try FileManager.default.createDirectory(at: trayBackupURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      try JSONEncoder().encode(items).write(to: trayBackupURL, options: .atomic)
    } catch {
      log.error("couldn't back up the Tray: \(error.localizedDescription, privacy: .public)")
    }
  }

  /// Fills the reply field a character at a time, like someone typing.
  private func type(_ text: String) {
    typing?.cancel()
    let model = NotificationHUDModel.shared
    guard let item = model.current else { return }
    typing = Task { @MainActor in
      for count in 1...text.count {
        model.replies.drafts[item.id] = String(text.prefix(count))
        try? await Task.sleep(for: .milliseconds(text[text.index(text.startIndex, offsetBy: count - 1)] == " " ? 110 : 65))
        if Task.isCancelled { return }
      }
    }
  }

  /// The island on the built-in (notched) display, else the first one.
  private var target: NotchPresentation? {
    let notched = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
    return notched.flatMap { shelf.presentation(onScreen: $0.frame) } ?? shelf.tourPresentation(requireVisible: false)
  }

  private func prepare() {
    if savedHideOnFullscreen == nil { savedHideOnFullscreen = AppSettings.shared.shellHideOnFullscreen }
    if savedTray == nil {
      // A copy on disk too, so a crash mid-filming can't lose the user's Tray (restored on next start).
      let items = Self.readTrayBackup() ?? FileTrayStore.shared.items
      Self.writeTrayBackup(items)
      savedTray = items
      FileTrayStore.shared.clear()
    }
    AppSettings.shared.shellHideOnFullscreen = false
    // The filming tool records the screen; without this the island shows its own Screen Recording activity.
    ScreenRecordingModel.shared.stop()
    useSampleData()
  }

  /// Swaps every source that shows personal data (music, clipboard, coding sessions, calendar, the
  /// browser skin) for `DemoSamples`, so nothing real can reach the recording.
  private func useSampleData() {
    guard savedMediaSettings == nil else { return }
    let settings = AppSettings.shared
    savedMediaSettings = (settings.discordPresenceEnabled, settings.liveVisualizerEnabled)
    settings.discordPresenceEnabled = false
    settings.liveVisualizerEnabled = false
    // Flashes follow the pointer's display by default; the film is of the built-in one.
    savedHUDTarget = settings.hudDisplayTarget
    settings.hudDisplayTarget = .allDisplays
    NowPlayingModel.shared.enterDemo(provider: DemoSamples.Player())
    PlayingNextModel.shared.setDemoBackend(DemoSamples.queueBackend())

    Self.clipboardOverride = DemoSamples.clipboardStore()
    Self.shelfOverride = DemoSamples.emptyShelf()

    AgentQuestionBridge.shared.shutdown()
    CodingAgentModel.shared.stop()
    CodingAgentModel.shared.setSessionsForPreview(DemoSamples.agentSessions())

    let notifications = NotificationHUDModel.shared
    // Real banners (Claude Code, Slack…) would show on camera; only demo messages may appear.
    notifications.stop()
    notifications.replies.useDemoTransport(DemoSamples.SilentReplies())
    savedInbox = notifications.replaceInboxForDemo(with: NotificationInbox())

    BrowserSkinModel.shared.stop()
    // The floating mini player would sit over the video's titles.
    LiquidPlayerController.shared.stop()

    let calendar = CalendarActivityModel.shared
    calendar.stop()
    savedPinnedCountdown = .some(calendar.pinned)
    calendar.pinned = nil
    showSampleCalendar()
    // A reminders fetch already in flight can still land; put the samples back after it.
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.showSampleCalendar() }
  }

  private func showSampleCalendar() {
    guard savedMediaSettings != nil else { return }
    let calendar = CalendarActivityModel.shared
    calendar.agenda = DemoSamples.agenda(calendar: calendar.weekCalendar)
    calendar.setMeeting(DemoSamples.meeting())
  }

  private func restoreRealData() {
    guard let saved = savedMediaSettings else { return }
    savedMediaSettings = nil
    NowPlayingModel.shared.exitDemo()
    PlayingNextModel.shared.setDemoBackend(nil)
    AppSettings.shared.discordPresenceEnabled = saved.discord
    AppSettings.shared.liveVisualizerEnabled = saved.visualizer
    if let target = savedHUDTarget { AppSettings.shared.hudDisplayTarget = target }
    savedHUDTarget = nil

    Self.clipboardOverride = nil
    Self.shelfOverride = nil

    CodingAgentModel.shared.setSessionsForPreview([])
    CodingAgentModel.shared.start()
    AgentQuestionBridge.shared.startIfEnabled()

    typing?.cancel()
    let notifications = NotificationHUDModel.shared
    notifications.replies.useDemoTransport(nil)
    if let savedInbox { _ = notifications.replaceInboxForDemo(with: savedInbox) }
    savedInbox = nil
    notifications.start()

    BrowserSkinModel.shared.start()
    LiquidPlayerController.shared.start()

    let calendar = CalendarActivityModel.shared
    if let pinned = savedPinnedCountdown { calendar.pinned = pinned }
    savedPinnedCountdown = nil
    calendar.agenda = []
    calendar.setMeeting(nil)
    calendar.start()
  }

  private func finish() {
    customize(false)
    usePill(false)
    RingMenuController.shared.close()
    FloatingBasketController.shared.closeAll()
    FloatingBasketController.shared.hideQuickActions()
    closeThumbnail()
    closeEditor()
    close()
    if let savedTray {
      FileTrayStore.shared.restore(savedTray)
    } else if !addedTrayItems.isEmpty {
      FileTrayStore.shared.remove(addedTrayItems)
    }
    savedTray = nil
    addedTrayItems = []
    try? FileManager.default.removeItem(at: Self.trayBackupURL)
    if let saved = savedHideOnFullscreen {
      AppSettings.shared.shellHideOnFullscreen = saved
      ScreenRecordingModel.shared.start()
    }
    savedHideOnFullscreen = nil
    restoreRealData()
  }

  private func usePill(_ on: Bool) {
    guard ShellEnvironment.demoForcesIsland != on else { return }
    ShellEnvironment.demoForcesIsland = on
    shelf.settingsChanged()
  }

  /// Same recipe as the Island Tour: navigate, then hold it open so the next tick expands it there.
  private func show(_ navigation: IslandNavigation) {
    guard let target else { return }
    withAnimation(NotchMotion.layout(reduceMotion: reduceMotion)) {
      target.selectedActivity = nil
      target.navigate(to: navigation)
    }
    shelf.setTourHold(.open, on: target)
  }

  private func close() {
    shelf.setTourHold(.none, on: nil)
    if let target { shelf.collapseForTour(target) }
  }

  private func customize(_ on: Bool) {
    if on { show(.showing(.home)) }
    withAnimation(NotchMotion.layout(reduceMotion: reduceMotion)) { HomeWidgetStore.shared.isEditing = on }
  }

  private func addToTray(_ urls: [URL]) {
    let before = Set(FileTrayStore.shared.items.map(\.id))
    _ = FileTrayStore.shared.add(urls)
    addedTrayItems.formUnion(Set(FileTrayStore.shared.items.map(\.id)).subtracting(before))
  }

  /// The same flashes the live monitors post, with demo values.
  private func show(_ flash: DemoCommand.Flash) {
    let flashes = IslandFlashCenter.shared
    switch flash {
    case .volume(let level):
      flashes.show(
        "Volume", symbol: HUDSymbol.volume(level: level, muted: false),
        tint: HUDTint.color(hex: AppSettings.shared.hudVolumeTintHex), value: level, duration: 1.6, kind: .volume)
    case .capsLock(let on):
      flashes.show(on ? "On" : "Off", symbol: on ? "capslock.fill" : "capslock", tint: on ? .green : .white)
    case .charging(let percent):
      flashes.show("Charging", symbol: "bolt.fill", tint: .green, value: Double(percent) / 100, duration: 2.6)
    case .unplugged(let percent):
      flashes.show("On battery", symbol: "battery.75percent", tint: .white, value: Double(percent) / 100)
    case .full:
      flashes.show(
        "Full Battery", symbol: "battery.100percent.bolt", tint: .green, duration: 5, detail: "Your Mac is fully charged.",
        shortTitle: "Full", autoOpenCard: 4, hero: true)
    case .airPods:
      let pods = AirPodsBatteries(name: "AirPods Pro", symbol: "airpodspro", left: 92, right: 88, caseLevel: 64, model: .airPodsPro)
      AirPodsConnectCard.present(pods, name: "AirPods Pro")
    case .camera:
      flashes.show("Camera on", symbol: "video.fill", tint: .green)
    case .microphone:
      flashes.show("Mic on", symbol: "mic.fill", tint: .orange)
    }
  }

  // MARK: - Capture thumbnail and editor

  /// The filmed display, not wherever the pointer or key window is.
  private var builtInScreen: NSScreen? { NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main }

  /// The thumbnail a finished capture shows, for a sample image. Nothing is copied or kept.
  private func showThumbnail(of url: URL) {
    guard let image = NSImage(contentsOf: url) else { return Self.log.error("demo: no image at \(url.path, privacy: .public)") }
    closeThumbnail()
    let id = UUID()
    thumbnailID = id
    CaptureThumbnailCenter.shared.show(image, id: id, displayID: builtInScreen?.thumbnailDisplayID)
  }

  private func closeThumbnail() {
    guard let id = thumbnailID else { return }
    thumbnailID = nil
    CaptureThumbnailCenter.shared.model(for: id)?.dismiss(.closed)
  }

  /// The real "Edit screenshot" window on a sample image. Done/close keeps nothing.
  private func openEditor(on url: URL) {
    guard let image = NSImage(contentsOf: url) else { return Self.log.error("demo: no image at \(url.path, privacy: .public)") }
    closeEditor()
    let controller = ShelfEditorWindowController(image: image, onSaveToShelf: { _ in })
    editor = controller
    if let window = controller.window, let screen = builtInScreen {
      // Against the left edge and narrower than the screen, so desktop widgets on the right (which
      // macOS draws over windows here) stay clear of it.
      let area = screen.visibleFrame
      let width = min(window.frame.width, area.width - 300)
      window.setFrame(CGRect(x: area.minX + 16, y: area.midY - window.frame.height / 2, width: width, height: window.frame.height), display: false)
    }
    controller.showWindow(nil)
    controller.window?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  private func closeEditor() {
    drawing?.cancel()
    // Done with a no-op destination: closes without the "Discard your edits?" sheet.
    editor?.done()
    editor = nil
  }

  /// Draws a mark the way a hand would: the shape grows over a fraction of a second, text types itself.
  private func draw(_ mark: DemoCommand.Mark) {
    guard let model = editor?.model else { return }
    drawing?.cancel()
    let height = model.image.size.height
    // Thicker than the editor's default, so the marks read in a scaled-down video.
    let style = AnnotationStyle(color: .systemRed, lineWidth: 10, fontSize: 76)
    // Commands use a top-left origin; the canvas is not flipped.
    func flip(_ point: CGPoint) -> CGPoint { CGPoint(x: point.x, y: height - point.y) }
    let start: Annotation
    let step: (Annotation, Double) -> Annotation
    let steps: Int
    switch mark {
    case .ellipse(let rect):
      let box = CGRect(x: rect.minX, y: height - rect.maxY, width: rect.width, height: rect.height)
      start = Annotation(tool: .ellipse, rect: CGRect(origin: CGPoint(x: box.midX, y: box.midY), size: .zero), style: style)
      step = { a, t in a.with(rect: box.insetBy(dx: box.width / 2 * (1 - t), dy: box.height / 2 * (1 - t))) }
      steps = 14
    case .arrow(let from, let to):
      let a = flip(from), b = flip(to)
      start = Annotation(tool: .arrow, points: [a, a], style: style)
      step = { annotation, t in annotation.with(points: [a, CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)]) }
      steps = 12
    case .text(let at, let text):
      let origin = flip(CGPoint(x: at.x, y: at.y + style.fontSize * 1.25))
      start = Annotation(tool: .text, rect: CGRect(origin: origin, size: .zero), style: style)
      step = { annotation, t in annotation.with(text: String(text.prefix(Int((Double(text.count) * t).rounded())))) }
      steps = text.count
    }
    model.session.addAnnotation(start)
    drawing = Task { @MainActor in
      var current = start
      for index in 1...max(1, steps) {
        try? await Task.sleep(for: .milliseconds(mark.isText ? 70 : 22))
        if Task.isCancelled { return }
        current = step(current, Self.easeOut(Double(index) / Double(max(1, steps)), linear: mark.isText))
        model.session.updateAnnotation(current)
      }
    }
  }

  private static func easeOut(_ t: Double, linear: Bool) -> Double { linear ? t : 1 - pow(1 - t, 3) }
}

private extension DemoCommand.Mark {
  var isText: Bool { if case .text = self { true } else { false } }
}
