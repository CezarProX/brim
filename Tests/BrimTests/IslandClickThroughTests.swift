import AppKit
import SwiftUI
import Testing

@testable import Brim

/// Clicks on the open island, delivered the way AppKit delivers them: the real `IslandPanel` at the
/// real hosting frame, not key, then synthesized mouse-down/up events through `sendEvent`.
@MainActor
@Suite(.serialized)
struct IslandClickThroughTests {
  enum Style: String, CaseIterable { case notch, pill }

  @MainActor struct Rig {
    let panel: IslandPanel
    let presentation: NotchPresentation
    let directory: URL

    /// A screen point (AppKit, bottom-left origin) to window coordinates.
    func windowPoint(_ screenPoint: CGPoint) -> CGPoint {
      CGPoint(x: screenPoint.x - panel.frame.minX, y: screenPoint.y - panel.frame.minY)
    }

    /// The capsule's rendered frame converted to screen coordinates.
    var renderedCapsule: CGRect? {
      guard let frame = presentation.capsuleFrameInWindow else { return nil }
      return CGRect(x: panel.frame.minX + frame.minX, y: panel.frame.maxY - frame.maxY,
                    width: frame.width, height: frame.height)
    }

    func click(atScreen point: CGPoint) async throws {
      let location = windowPoint(point)
      for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
        let event = try #require(NSEvent.mouseEvent(
          with: type, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
          windowNumber: panel.windowNumber, context: nil, eventNumber: 0, clickCount: 1,
          pressure: type == .leftMouseDown ? 1 : 0))
        panel.sendEvent(event)
        try await Task.sleep(for: .milliseconds(40))
      }
      try await Task.sleep(for: .milliseconds(250))
    }

    /// Screen frame of the accessibility element with this label (a SwiftUI button's label).
    func frame(ofLabel label: String) -> CGRect? {
      var queue: [Any] = panel.contentView.map { [$0] } ?? []
      var visited = 0
      while !queue.isEmpty, visited < 4000 {
        let element = queue.removeFirst()
        visited += 1
        guard let node = element as? NSAccessibilityProtocol else { continue }
        if (node.accessibilityLabel()) == label, true { return node.accessibilityFrame() }
        queue.append(contentsOf: node.accessibilityChildren() ?? [])
      }
      return nil
    }

    func labels() -> [String] {
      var queue: [Any] = panel.contentView.map { [$0] } ?? []
      var out: [String] = []
      while !queue.isEmpty, out.count < 400 {
        let element = queue.removeFirst()
        guard let node = element as? NSAccessibilityProtocol else { continue }
        if let label = node.accessibilityLabel(), !label.isEmpty { out.append(label) }
        queue.append(contentsOf: node.accessibilityChildren() ?? [])
      }
      return out
    }

    func close() {
      panel.orderOut(nil)
      panel.contentView = nil
      try? FileManager.default.removeItem(at: directory)
    }
  }

  static let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)

  static func geometry(_ style: Style) -> NotchGeometry {
    style == .notch
      ? NotchGeometry(screenFrame: screen, notchWidth: 184, notchHeight: 32)
      : NotchGeometry.dynamicIsland(screenFrame: screen)
  }

  private func settings() -> AppSettings {
    AppSettings(defaults: UserDefaults(suiteName: "qs-click-\(UUID().uuidString)")!)
  }

  private func makeRig(_ style: Style, music: Bool, log: CommandLog = CommandLog(), configure: (NotchPresentation) -> Void = { _ in }) async throws -> Rig {
    let presentation = NotchPresentation()
    let geometry = Self.geometry(style)
    presentation.geometry = geometry
    presentation.isExpanded = true
    configure(presentation)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let player = NowPlayingModel(provider: ClickTestPlayer(known: music, log: log), enabledSources: music ? [.music] : [])
    if music { await player.refreshNow() }
    let view = NotchShelfView(
      presentation: presentation, store: ShelfStore(directory: directory), nowPlaying: player,
      calls: CallActivityModel(accessibilityTrusted: { false }), recording: ScreenRecordingModel(probe: { nil }),
      timers: NativeTimerModel(), tray: FileTrayStore(directory: directory.appendingPathComponent("tray")),
      homeWidgets: HomeWidgetStore(widgets: [.clock, .timer, .stats], persist: { _ in }),
      notifications: NotificationHUDModel(settings: settings()), glances: IslandGlanceModel(settings: settings()),
      theme: IslandTheme(surface: .dynamicGlass), weather: WeatherStore(settings: settings()),
      playingNext: PlayingNextModel(read: { _ in "" }, perform: { _ in "" }, fetchArtwork: { _ in nil }))
    let panel = IslandPanel.make(frame: geometry.hostingFrame)
    panel.contentView = IslandPanel.host(view)
    panel.keyAllowed = true
    panel.ignoresMouseEvents = false
    panel.orderFrontRegardless()
    let rig = Rig(panel: panel, presentation: presentation, directory: directory)
    try await settle(rig)
    return rig
  }

  private func settle(_ rig: Rig) async throws {
    rig.panel.contentView?.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(700))
    rig.panel.contentView?.layoutSubtreeIfNeeded()
  }

  /// The centre of each page button in screen coordinates, from the rendered capsule.
  private func tabCenters(_ capsule: CGRect) -> [IslandPage: CGPoint] {
    // The rig's tray is empty, so its tab is hidden.
    let pages = IslandPageOrder.visible(trayCount: 0, current: .home)
    let inner = capsule.insetBy(dx: IslandNavigationLayout.inset, dy: 0)
    let step = inner.width / CGFloat(pages.count)
    return Dictionary(uniqueKeysWithValues: pages.enumerated().map { index, page in
      (page, CGPoint(x: inner.minX + step * (CGFloat(index) + 0.5), y: capsule.midY))
    })
  }

  @Test(arguments: [(Style.notch, false), (.notch, true), (.pill, false), (.pill, true)])
  func capsuleHitFrameMatchesRenderedCapsule(style: Style, music: Bool) async throws {
    let rig = try await makeRig(style, music: music)
    defer { rig.close() }
    let rendered = try #require(rig.renderedCapsule)
    let hit = rig.presentation.geometry.navigationFrame
    #expect(abs(rendered.midY - hit.midY) < 1, "capsule drawn at \(rendered), hit-tested at \(hit)")
    #expect(abs(rendered.height - hit.height) < 1)
    #expect(hit.minX <= rendered.minX + 0.5 && hit.maxX >= rendered.maxX - 0.5)
    #expect(rig.panel.frame.contains(rendered), "capsule \(rendered) outside window \(rig.panel.frame)")
  }

  @Test(arguments: [(Style.notch, false), (.notch, true), (.pill, false), (.pill, true)])
  func firstClickOnEachTabSwitchesPage(style: Style, music: Bool) async throws {
    let rig = try await makeRig(style, music: music)
    defer { rig.close() }
    #expect(!rig.panel.isKeyWindow)
    for page in [IslandPage.clipboard, .widgets, .home, .widgets, .clipboard] {
      try await settle(rig)
      let capsule = try #require(rig.renderedCapsule)
      let center = try #require(tabCenters(capsule)[page])
      try await rig.click(atScreen: center)
      #expect(rig.presentation.navigation.page == page, "clicking \(page) at \(center) left \(rig.presentation.navigation.page)")
    }
  }

  /// Switching to a shorter (or taller) page moves the capsule out from under a pointer that has
  /// not moved. The hover must not read that as the pointer leaving: it used to collapse the island
  /// 0.1 s later, and collapsing resets the page to Home, so the click looked like it did nothing.
  @Test(arguments: [(Style.notch, false), (.notch, true), (.pill, false), (.pill, true)])
  func pageSwitchUnderStillPointerKeepsIslandOpen(style: Style, music: Bool) async throws {
    let rig = try await makeRig(style, music: music)
    defer { rig.close() }
    var hold = IslandPointerHold()
    for page in [IslandPage.widgets, .clipboard, .home, .widgets, .home, .clipboard] {
      try await settle(rig)
      let capsule = try #require(rig.renderedCapsule)
      let center = try #require(tabCenters(capsule)[page])
      let before = rig.presentation.geometry
      let heldBefore = hold.update(pointer: center, inside: before.containsPointer(center, expanded: true), expanded: true)
      #expect(heldBefore)
      try await rig.click(atScreen: center)
      try await settle(rig)
      #expect(rig.presentation.navigation.page == page)
      var hover = ShelfHoverState()
      hover.forceOpen()
      var open = true
      for tick in 0..<20 {
        let after = rig.presentation.geometry
        let inside = hold.update(pointer: center, inside: after.containsPointer(center, expanded: true), expanded: true)
        open = hover.update(isInside: inside, isDragging: false, now: Double(tick) / 30)
      }
      #expect(open, "island collapsed after switching to \(page) under a still pointer")
    }
  }

  /// Moving from the shell down to the capsule crosses the gap between them; a slow approach
  /// (40 pt/s) must not count as leaving the island.
  @Test(arguments: Style.allCases)
  func slowApproachToCapsuleKeepsIslandOpen(style: Style) async throws {
    let rig = try await makeRig(style, music: false)
    defer { rig.close() }
    let geometry = rig.presentation.geometry
    let capsule = try #require(rig.renderedCapsule)
    var hover = ShelfHoverState()
    hover.forceOpen()
    var hold = IslandPointerHold()
    var y = geometry.panelFrame.minY + 10
    var now: TimeInterval = 0
    while y > capsule.midY {
      let point = CGPoint(x: capsule.midX, y: y)
      let inside = hold.update(pointer: point, inside: geometry.containsPointer(point, expanded: true), expanded: true)
      let open = hover.update(isInside: inside, isDragging: false, now: now)
      #expect(open, "collapsed at y=\(y)")
      y -= 40.0 / 30
      now += 1.0 / 30
    }
  }

  /// The camera band (notched Mac) or the pill's small top margin above the page content.
  private func band(_ style: Style) -> CGFloat { style == .notch ? 32 : 4 }

  /// A widget tile, the back chevron of the widget it opens, and a second tile all take the first click.
  @Test(arguments: Style.allCases)
  func widgetTilesAndBackChevronTakeFirstClick(style: Style) async throws {
    let rig = try await makeRig(style, music: false) { $0.navigate(to: .showing(.widgets)) }
    defer { rig.close() }
    let frame = rig.panel.frame
    let gridLeft = frame.midX - IslandPageLayout.widgetsWidth / 2
      + (IslandPageLayout.widgetsWidth - CGFloat(IslandWidgetGrid.columns) * IslandWidgetGrid.columnWidth) / 2
    let iconY = frame.maxY - band(style) - IslandWidgetGrid.topPadding - IslandWidgetGrid.iconSize / 2
    let tiles = IslandWidgetTile.visible(hasRecordingResult: RecordingResultModel.shared.result != nil)
    for column in [0, 3] {
      let tile = tiles[column]
      try await rig.click(atScreen: CGPoint(x: gridLeft + IslandWidgetGrid.columnWidth * (CGFloat(column) + 0.5), y: iconY))
      #expect(rig.presentation.navigation.openedWidget == tile, "tile \(tile) did not open")
      try await settle(rig)
      let top = style == .notch ? band(style) : 10
      let chevron = CGPoint(x: frame.midX - IslandPageLayout.widgetsWidth / 2 + 28 + 13, y: frame.maxY - top - 8 - 14)
      try await rig.click(atScreen: chevron)
      #expect(rig.presentation.navigation.openedWidget == nil, "back chevron did not close \(tile)")
      try await settle(rig)
    }
  }

  /// The player's transport (on the Music page) takes the first click: sweep down the centre of the
  /// controls column and expect a play/pause to reach the player.
  @Test(arguments: Style.allCases)
  func playerTransportTakesFirstClick(style: Style) async throws {
    let log = CommandLog()
    let rig = try await makeRig(style, music: true, log: log) { $0.navigate(to: .showing(.music)) }
    defer { rig.close() }
    let size = MusicPlayerCard.preferredSize(showsQueue: false, topInset: style == .notch ? 45 : 20)
    let x = rig.panel.frame.midX - (rig.presentation.geometry.expandedSize.width) / 2
      + MusicPlayerCard.sideInset + MusicPlayerCard.columnWidth / 2
    var y = rig.panel.frame.maxY - size.height + 8
    while log.all.isEmpty, y < rig.panel.frame.maxY - size.height + 60 {
      try await rig.click(atScreen: CGPoint(x: x, y: y))
      y += 6
    }
    try await Task.sleep(for: .milliseconds(300))
    #expect(log.all.contains("playPause"), "no transport command reached the player: \(log.all)")
  }

  /// Tall pages (the clipboard opens 380 pt high) must keep the capsule inside the window.
  @Test(arguments: Style.allCases)
  func capsuleStaysClickableUnderTallestPage(style: Style) async throws {
    let rig = try await makeRig(style, music: false) { $0.navigate(to: .opening(.clipboard)) }
    defer { rig.close() }
    let capsule = try #require(rig.renderedCapsule)
    #expect(rig.panel.frame.contains(capsule), "capsule \(capsule) outside window \(rig.panel.frame)")
    try await rig.click(atScreen: try #require(tabCenters(capsule)[.home]))
    #expect(rig.presentation.navigation.page == .home)
  }
}

/// Records the transport commands the player card sends.
final class CommandLog: @unchecked Sendable {
  private let lock = NSLock()
  private var commands: [String] = []
  func append(_ command: NowPlayingCommand) { lock.withLock { commands.append("\(command)") } }
  var all: [String] { lock.withLock { commands } }
}

private struct ClickTestPlayer: NowPlayingProviding {
  var known: Bool
  var log = CommandLog()
  func connect(_ source: NowPlayingSource) async throws {}
  func snapshot(_ source: NowPlayingSource) async throws -> NowPlayingSnapshot? {
    guard known else { return nil }
    return NowPlayingSnapshot(source: .music, title: "Kill Bill", artist: "SZA", album: "SOS", duration: 153,
                              position: 69, isPlaying: true)
  }
  func perform(_ command: NowPlayingCommand, expected: NowPlayingSnapshot, token: NowPlayingActionToken) async throws {
    log.append(command)
  }
}
