import CoreGraphics
import Foundation
import Testing

@testable import Brim

/// The Island Tour's step model: which island change completes which step, Back / Next / Skip,
/// what finishing records, where the card sits, and that every line is translated.
@MainActor
struct IslandTourTests {
  private func shot(_ expanded: Bool, _ page: IslandPage = .home) -> IslandTourSnapshot {
    IslandTourSnapshot(expanded: expanded, page: page)
  }

  /// Feeds one island state; `#expect` can't call a mutating method itself.
  private func step(_ session: inout IslandTourSession, _ snapshot: IslandTourSnapshot) -> Bool {
    session.observe(snapshot)
  }

  private func session(at step: IslandTourStep, seeing snapshot: IslandTourSnapshot) -> IslandTourSession {
    var session = IslandTourSession()
    while session.step != step { session.next() }
    session.observe(snapshot)
    return session
  }

  @Test func openingTheIslandCompletesTheFirstStep() {
    var session = IslandTourSession()
    #expect(!step(&session, shot(false)))
    #expect(session.step == .open)
    #expect(step(&session, shot(true)))
    #expect(session.step == .home)
  }

  /// Started from the island's own menu, the island is already open: the first step passes at once.
  @Test func anAlreadyOpenIslandPassesTheFirstStep() {
    var session = IslandTourSession()
    #expect(step(&session, shot(true)))
    #expect(session.step == .home)
  }

  /// Going Back to the first step with the island open waits for a real reopen.
  @Test func backToTheFirstStepWaitsForAReopen() {
    var session = IslandTourSession()
    session.observe(shot(true))
    session.back()
    #expect(session.step == .open)
    #expect(!step(&session, shot(true)))
    #expect(!step(&session, shot(false)))
    #expect(step(&session, shot(true)))
  }

  /// Each page step is shown by the tour; tapping on to the next step's tab is the user doing it.
  @Test func tappingOnToTheNextTabCompletesAPageStep() {
    var session = session(at: .home, seeing: shot(true, .home))
    #expect(!step(&session, shot(true, .widgets)))
    #expect(step(&session, shot(true, .clipboard)))
    #expect(session.step == .clipboard)
    #expect(step(&session, shot(true, .music)))
    #expect(session.step == .music)
    #expect(step(&session, shot(true, .widgets)))
    #expect(session.step == .widgets)
    // Widgets, Tray and right-click wait for Next.
    #expect(!step(&session, shot(true, .tray)))
    #expect(session.step == .widgets)
  }

  /// The tour's own page switch is the baseline, never the user doing the step.
  @Test func theTourOwnDemoDoesNotCount() {
    var session = session(at: .home, seeing: shot(true, .home))
    session.next()
    session.rebase(shot(true, .clipboard))
    #expect(!step(&session, shot(true, .clipboard)))
    #expect(session.step == .clipboard)
    session.next()
    session.next()
    session.next()
    session.next()
    #expect(session.step == .swipe)
    session.rebase(shot(true, .home))
    #expect(!step(&session, shot(true, .home)))
    #expect(step(&session, shot(true, .clipboard)), "a swipe to another tab completes the swipe step")
    #expect(session.step == .rightClick)
  }

  @Test func anyPageChangeCompletesTheSwipeStep() {
    var session = session(at: .swipe, seeing: shot(true, .home))
    #expect(!step(&session, shot(true, .home)))
    #expect(!step(&session, shot(false, .home)))
    session.rebase(shot(true, .home))
    #expect(step(&session, shot(true, .music)))
    #expect(session.step == .rightClick)
  }

  /// The closed-island step closes the island; opening it again is the user trying it.
  @Test func reopeningTheIslandCompletesTheClosedStep() {
    var session = session(at: .closed, seeing: shot(false, .home))
    #expect(!step(&session, shot(false)))
    #expect(step(&session, shot(true)))
    #expect(session.step == .done)
    #expect(!step(&session, shot(false)))
    #expect(session.step == .done && session.isRunning)
  }

  /// What each step shows on the real island, and what its arrow points at.
  @Test func eachStepDemonstratesItsPageAndPointsAtIt() {
    let expected: [(IslandTourStep, IslandTourDemo, IslandTourTarget)] = [
      (.open, .closed, .notch), (.home, .page(.home), .tab(.home)),
      (.clipboard, .page(.clipboard), .tab(.clipboard)), (.music, .page(.music), .tab(.music)),
      (.widgets, .page(.widgets), .tab(.widgets)), (.tray, .page(.tray), .tab(.tray)),
      (.swipe, .page(.home), .islandBody), (.rightClick, .page(.home), .tabBar),
      (.closed, .closed, .notch), (.done, .none, .none),
    ]
    #expect(expected.map(\.0) == IslandTourStep.allCases)
    for (step, demo, target) in expected {
      #expect(step.demo == demo, "\(step) demo")
      #expect(step.target == target, "\(step) target")
    }
  }

  @Test func nextOnTheLastStepFinishes() {
    var session = IslandTourSession()
    for _ in 1..<IslandTourSession.count { session.next() }
    #expect(session.step == .done && session.position == IslandTourSession.count)
    session.next()
    #expect(session.outcome == .finished && !session.isRunning)
    session.back()
    #expect(session.step == .done)
  }

  @Test func skipStopsAndIgnoresTheIsland() {
    var session = IslandTourSession()
    session.skip()
    #expect(session.outcome == .skipped)
    #expect(!step(&session, shot(true)))
    #expect(session.step == .open)
  }

  @Test func backStopsAtTheFirstStep() {
    var session = IslandTourSession()
    session.back()
    #expect(session.step == .open && session.position == 1)
    session.next()
    session.back()
    #expect(session.step == .open)
  }

  /// Steps that show a page hold the island open; the open, closed and last steps let it be.
  @Test func holdsMatchWhatEachStepNeeds() {
    for step in [IslandTourStep.open, .closed, .done] { #expect(step.hold == .none) }
    for step in [IslandTourStep.home, .clipboard, .music, .widgets, .tray, .swipe, .rightClick] {
      #expect(step.hold == .open)
    }
  }

  /// Only what the tour can't show by itself asks the user to try it.
  @Test func onlyTheDoingStepsSayTryItNow() {
    let tries = IslandTourStep.allCases.filter { $0.waitsForAction(IslandTourContext()) }
    #expect(tries == [.open, .swipe])
  }

  @Test func theTourStartsByItselfOnlyOnceWithTheIslandOn() {
    #expect(IslandTourPolicy.startsAutomatically(islandEnabled: true, introductionDone: true, tourDone: false))
    #expect(!IslandTourPolicy.startsAutomatically(islandEnabled: false, introductionDone: true, tourDone: false))
    #expect(!IslandTourPolicy.startsAutomatically(islandEnabled: true, introductionDone: false, tourDone: false))
    #expect(!IslandTourPolicy.startsAutomatically(islandEnabled: true, introductionDone: true, tourDone: true))
  }

  @Test(arguments: [IslandTourSession.Outcome.finished, .skipped])
  func finishingOrSkippingIsRemembered(_ outcome: IslandTourSession.Outcome) throws {
    let suite = "island-tour-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AppSettings(defaults: defaults)
    #expect(!settings.islandTourCompleted)
    IslandTourPolicy.record(outcome, in: settings)
    #expect(AppSettings(defaults: defaults).islandTourCompleted)
    #expect(!SettingsTransfer.isExportable(key: "islandTourCompleted"))
  }

  /// The card sits under the island (under the tab bar when open), centred, clear of the island's hover area.
  @Test(arguments: [false, true])
  func theCardSitsClearOfTheIsland(floating: Bool) {
    let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    var geometry = floating
      ? NotchGeometry.dynamicIsland(screenFrame: screen)
      : NotchGeometry.make(screenFrame: screen, hardwareNotch: (185, 32), style: .notch, tuning: ShellTuning())
    geometry.utilityContentHeight = 250
    geometry.preferredWidth = 556
    let size = CGSize(width: IslandTourCard.width + 20, height: 150)
    for expanded in [false, true] {
      let frame = IslandTourLayout.panelFrame(geometry: geometry, expanded: expanded, size: size)
      let card = frame.insetBy(dx: IslandTourLayout.shadowMargin, dy: IslandTourLayout.shadowMargin)
      #expect(abs(frame.midX - screen.midX) <= 1)
      let island = expanded ? geometry.navigationFrame : geometry.triggerFrame
      #expect(card.maxY <= island.minY - IslandTourLayout.gap + 1)
      #expect(card.maxY > island.minY - IslandTourLayout.gap - 10, "the card stays close to the island")
      for x in stride(from: card.minX, through: card.maxX, by: 20) {
        #expect(!geometry.containsPointer(CGPoint(x: x, y: card.maxY - 1), expanded: expanded))
      }
    }
  }

  /// The arrow's tip lands on each tab of the capsule, in order, and under the notch when closed;
  /// it always falls inside the click-through overlay and above the card.
  @Test(arguments: [false, true])
  func theArrowPointsAtEachTab(floating: Bool) {
    let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    var geometry = floating
      ? NotchGeometry.dynamicIsland(screenFrame: screen)
      : NotchGeometry.make(screenFrame: screen, hardwareNotch: (185, 32), style: .notch, tuning: ShellTuning())
    geometry.utilityContentHeight = 250
    geometry.preferredWidth = 556
    let pages = IslandPageOrder.visible(trayCount: 3, current: .home)
    let capsuleWidth = pages.reduce(2 * IslandNavigationLayout.inset) {
      $0 + ($1 == .tray ? IslandTourPointerGeometry.trayTabWithCount : IslandTourPointerGeometry.tabWidth) + 2
    } - 2
    geometry.navigationWidth = capsuleWidth
    let capsule = geometry.navigationFrame
    let overlay = IslandTourPointerGeometry.overlayFrame(for: geometry)
    var lastX = -CGFloat.infinity
    for page in pages {
      let anchor = IslandTourPointerGeometry.anchor(
        for: .tab(page), geometry: geometry, expanded: true, pages: pages, trayCount: 3)
      guard let anchor else { Issue.record("no anchor for \(page)"); continue }
      #expect(!anchor.swipe)
      #expect(anchor.point.x > lastX && anchor.point.x > capsule.minX && anchor.point.x < capsule.maxX)
      #expect(abs(anchor.point.y - capsule.minY) <= 4, "the tip touches the tab's lower edge")
      #expect(overlay.contains(anchor.point))
      lastX = anchor.point.x
    }
    #expect(IslandTourPointerGeometry.anchor(for: .tab(.music), geometry: geometry, expanded: false, pages: pages, trayCount: 3) == nil)
    let notch = IslandTourPointerGeometry.anchor(for: .notch, geometry: geometry, expanded: false, pages: pages, trayCount: 3)
    #expect(notch.map { abs($0.point.x - geometry.triggerFrame.midX) < 1 && $0.point.y < geometry.triggerFrame.minY } == true)
    let swipe = IslandTourPointerGeometry.anchor(for: .islandBody, geometry: geometry, expanded: true, pages: pages, trayCount: 3)
    #expect(swipe.map { $0.swipe && geometry.panelFrame.contains($0.point) } == true)
    // The arrow (tip down to its tail) fits between the tab bar and the card.
    let card = IslandTourLayout.panelFrame(geometry: geometry, expanded: true, size: CGSize(width: 360, height: 150))
      .insetBy(dx: IslandTourLayout.shadowMargin, dy: IslandTourLayout.shadowMargin)
    #expect(card.maxY <= capsule.minY - IslandTourLayout.arrowLength)
  }

  @Test func tabCentresFollowTheCapsuleLayout() {
    let capsule = CGRect(x: 100, y: 0, width: 200, height: 38)
    let pages: [IslandPage] = [.home, .clipboard, .music, .widgets]
    let centres = pages.compactMap {
      IslandTourPointerGeometry.tabCenter($0, pages: pages, trayCount: 0, capsule: capsule)?.x
    }
    let expected: [CGFloat] = [119, 151, 183, 215]  // 100 + inset 4 + 32 per tab + half a tab
    #expect(centres == expected)
    #expect(IslandTourPointerGeometry.tabCenter(.tray, pages: pages, trayCount: 0, capsule: capsule) == nil)
  }

  /// Every step's copy, in every variant, ships in both string tables.
  @Test func everyTourLineIsTranslated() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent()
    let ro = try #require(NSDictionary(contentsOf: root.appendingPathComponent("Resources/ro.lproj/Localizable.strings")) as? [String: String])
    let en = try #require(NSDictionary(contentsOf: root.appendingPathComponent("Resources/en.lproj/Localizable.strings")) as? [String: String])
    var keys = Set(IslandPage.allCases.map(\.title))
    for step in IslandTourStep.allCases {
      keys.insert(step.title)
      for track in [false, true] {
        for floating in [false, true] {
          for hover in [false, true] {
            keys.formUnion(step.lines(IslandTourContext(hasTrack: track, floating: floating, opensOnHover: hover)))
          }
        }
      }
    }
    for key in keys.sorted() {
      #expect(ro[key] != nil && en[key] != nil, "missing translation: \(key)")
    }
  }
}
