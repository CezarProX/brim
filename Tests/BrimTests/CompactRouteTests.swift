import Foundation
import SwiftUI
import Testing

@testable import Brim

/// The closed island's priority order:
/// recording > call > HUD flash > notification > needs-input agent > timer/dictation > music > glances.
struct CompactRouteTests {
  private func flash(_ kind: HUDKind = .volume) -> IslandFlash {
    IslandFlash(title: "Volume", symbol: "speaker.wave.2.fill", tint: .green, value: 0.4,
                until: .distantFuture, kind: kind)
  }

  private func resolve(
    recording: Bool = false, call: Bool = false, music: Bool = false, timer: Bool = false,
    needsInput: Bool = false, agent: Bool = false, dictation: Bool = false,
    flash: IslandFlash? = nil, notification: Bool = false
  ) -> CompactRoute {
    var extra: [IslandActivity] = []
    if agent || needsInput { extra.append(.agent) }
    if dictation { extra.append(.dictation) }
    if flash != nil { extra.append(.system) }
    let activities = IslandActivities(recording: recording, call: call, music: music, timer: timer,
                                      agentNeedsInput: needsInput, additional: extra)
    return CompactRoute.resolve(activities: activities, flash: flash, hasNotification: notification)
  }

  @Test func nothingLiveIsIdleSoGlancesCanShow() {
    #expect(resolve() == .idle)
  }

  @Test func musicAloneLeadsTheCompactIsland() {
    #expect(resolve(music: true) == .activity(.music))
  }

  @Test func hudFlashBeatsMusicTimerAndAgents() {
    let f = flash()
    #expect(resolve(music: true, flash: f) == .hud(f))
    #expect(resolve(timer: true, flash: f) == .hud(f))
    #expect(resolve(needsInput: true, flash: f) == .hud(f))
    #expect(resolve(dictation: true, flash: f) == .hud(f))
  }

  @Test func recordingAndCallsBeatTheHUD() {
    let f = flash()
    #expect(resolve(recording: true, flash: f) == .activity(.recording))
    #expect(resolve(call: true, flash: f, notification: true) == .activity(.call))
    #expect(resolve(recording: true, call: true, flash: f) == .activity(.recording))
  }

  @Test func notificationBeatsAgentsTimersAndMusicButNotHUD() {
    #expect(resolve(music: true, notification: true) == .notification)
    #expect(resolve(timer: true, notification: true) == .notification)
    #expect(resolve(needsInput: true, notification: true) == .notification)
    let f = flash()
    #expect(resolve(flash: f, notification: true) == .hud(f))
    #expect(resolve(call: true, notification: true) == .activity(.call))
  }

  @Test func agentNeedingInputRanksJustUnderCalls() {
    #expect(resolve(timer: true, needsInput: true) == .activity(.agent))
    #expect(resolve(music: true, needsInput: true) == .activity(.agent))
    #expect(resolve(needsInput: true, dictation: true) == .activity(.agent))
    #expect(resolve(call: true, needsInput: true) == .activity(.call))
    #expect(resolve(recording: true, needsInput: true) == .activity(.recording))
  }

  @Test func aWorkingAgentStillYieldsToTimerAndMusic() {
    #expect(resolve(timer: true, agent: true) == .activity(.timer))
    #expect(resolve(music: true, agent: true) == .activity(.music))
  }

  @Test func musicKeepsTheIslandOverTimerButDictationOutranksIt() {
    #expect(resolve(music: true, timer: true) == .activity(.music))
    #expect(resolve(music: true, dictation: true) == .activity(.dictation))
  }

  @Test func needsInputOnlyMarksAgentRouteAsTappableToJump() {
    let activities = IslandActivities(recording: false, call: false, music: false, agentNeedsInput: true,
                                      additional: [.agent])
    #expect(CompactRoute.activity(.agent).isAgentNeedingInput(activities))
    #expect(!CompactRoute.activity(.music).isAgentNeedingInput(activities))
    let calm = IslandActivities(recording: false, call: false, music: false, additional: [.agent])
    #expect(!CompactRoute.activity(.agent).isAgentNeedingInput(calm))
  }

  @Test func flashesWithNoOtherActivityStillResolveToHUD() {
    let f = flash(.drive)
    #expect(resolve(flash: f) == .hud(f))
  }
}

struct CompactRouteGeometryTests {
  private let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
  private func notched(_ route: CompactRoute) -> NotchGeometry {
    var g = NotchGeometry(screenFrame: screen, notchWidth: 184, notchHeight: 32)
    g.route = route
    return g
  }
  private func flash(action: Bool = false) -> IslandFlash {
    IslandFlash(title: "Drive", symbol: "externaldrive.fill", tint: .white, value: nil, until: .distantFuture,
                kind: .drive, action: action ? HUDAction(title: "Eject", symbol: "eject.fill") {} : nil)
  }

  @Test func hudStripIsNotchWidthPlusWings() {
    let g = notched(.hud(flash()))
    #expect(g.collapsedSize == CGSize(width: 184 + 2 * HUDMetrics.wing + 2 * g.hudShoulder, height: 32))
  }

  @Test func hudCardGrowsOnHoverAndCoversTheStrip() {
    var g = notched(.hud(flash(action: true)))
    let strip = g.collapsedSize
    g.hudHovered = true
    #expect(g.collapsedSize.width > strip.width && g.collapsedSize.height > strip.height)
    #expect(g.triggerFrame.contains(CGPoint(x: screen.midX, y: screen.maxY - 5)))
  }

  @Test func belowNotchStripHangsUnderTheCameraAsOneCentredGroup() {
    var g = notched(.hud(flash()))
    g.hudPlacement = .belowNotch
    #expect(g.collapsedSize.height == 64)
    // No camera in the lower band, so glyph + label are one centred group there (no split wings):
    // a short label hangs as wide as the housing; a long one widens it to fit.
    #expect(g.collapsedSize.width == 184 + 2 * g.hudShoulder)
    #expect(g.hudMetrics.belowStripWidth(for: flash()) == 184)
    g.hudHovered = true
    #expect(g.collapsedSize.height > 64)
  }

  @Test func pillHUDHasNoPhantomNotchGap() {
    var g = NotchGeometry(screenFrame: screen, notchWidth: 0, notchHeight: 0, topInset: 8)
    g.route = .hud(flash())
    // One centred glyph + label group: a short label keeps the idle pill's width, no split wings.
    #expect(g.collapsedSize.width == NotchGeometry.islandClosedWidth)
    #expect(g.hudMetrics.floating)
    g.hudPlacement = .belowNotch  // no camera to hang under: stays beside
    #expect(g.collapsedSize.height == NotchGeometry.islandHeight)
  }

  @Test func glanceWingsWidenTheIdleNotchAndKeepTheCameraCentered() {
    var g = notched(.idle)
    let base = g.collapsedSize.width
    g.glanceLeft = 64
    g.glanceRight = 64
    #expect(g.collapsedSize.width == base + 2 * (64 + NotchGeometry.glanceWingPadding))
    #expect(g.collapsedMainOffset == 0)
    g.glanceRight = 0
    #expect(g.collapsedSize.width == base + 64 + NotchGeometry.glanceWingPadding)
    // Wider on the left: the shape grows leftwards so the housing stays over the notch.
    #expect(g.collapsedMainOffset < 0)
    let leftEdge = g.triggerFrame.minX
    #expect(abs((screen.midX - 92) - (leftEdge + (64 + NotchGeometry.glanceWingPadding))) < 0.5)
  }

  @Test func trackTitleWidensOnlyTheMusicIsland() {
    var g = notched(.activity(.music))
    g.hasLiveActivity = true
    g.compactActivity = .music
    let plain = g.collapsedSize.width
    g.compactTitleWidth = 96
    #expect(g.collapsedSize.width == plain + 102)
    #expect(g.collapsedMainOffset == -51)
    var timer = notched(.activity(.timer))
    timer.hasLiveActivity = true
    timer.compactActivity = .timer
    let before = timer.collapsedSize.width
    timer.compactTitleWidth = 96
    #expect(timer.collapsedSize.width == before)
  }

  @Test func notificationWingsAndOpenCard() {
    var g = notched(.notification)
    #expect(g.collapsedSize.width == 184 + 2 * NotchGeometry.notificationWing)
    g.notificationBodyHeight = 90
    #expect(g.expandedSize == CGSize(width: NotchGeometry.notificationCardWidth + 24, height: 32 + 90))
  }

  @Test func hudQueueKeepsAHeldFlashAndLingersOnRelease() {
    var queue = HUDQueue()
    let now = Date()
    queue.offer(IslandFlash(title: "a", symbol: "x", tint: .white, value: nil, until: now.addingTimeInterval(0.2)), now: now)
    queue.ensureRemaining(0.9, now: now)
    #expect(queue.current?.until == now.addingTimeInterval(0.9))
    queue.ensureRemaining(0.1, now: now)
    #expect(queue.current?.until == now.addingTimeInterval(0.9))
  }
}
