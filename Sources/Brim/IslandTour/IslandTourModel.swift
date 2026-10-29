import Foundation

// The Island Tour's pure logic: the steps, their copy, which island change completes each one,
// and how Back / Next / Skip move through them. Nothing here touches AppKit, so it is unit-tested.

/// What the tour reads off the island each time something changes.
struct IslandTourSnapshot: Equatable {
  var expanded = false
  var page: IslandPage = .home
}

/// How the tour keeps the island open while a step is on screen.
enum IslandTourHold: Equatable {
  /// The island behaves as usual.
  case none
  /// The island stays open even when the pointer leaves for the tour card.
  case open
  /// Open until the pointer visits the island and leaves again (like ⌥⌘N).
  case untilPointerLeaves
}

/// Copy that depends on the Mac: whether music is known, whether the island is the floating pill,
/// and whether hovering opens it (Settings > Island can turn that off; a click still works).
struct IslandTourContext: Equatable {
  var hasTrack = false
  var floating = false
  var opensOnHover = true
}

/// What the tour does to the real island when a step comes up (Next, Back, or the user doing it).
enum IslandTourDemo: Equatable {
  /// Leave the island as it is.
  case none
  /// Close it, to show the closed island (or to let the user open it).
  case closed
  /// Open it on this page, as if the user had tapped its tab.
  case page(IslandPage)
}

/// What the tour's arrow points at.
enum IslandTourTarget: Equatable {
  case none
  /// The closed notch (or pill).
  case notch
  /// One tab in the open island's tab bar.
  case tab(IslandPage)
  /// The open island's body, where two fingers swipe.
  case islandBody
  /// The whole tab bar, for right-click.
  case tabBar
}

enum IslandTourStep: Int, CaseIterable, Identifiable {
  case open, home, clipboard, music, widgets, tray, swipe, rightClick, closed, done

  var id: Int { rawValue }

  var title: String {
    switch self {
    case .open: "Open the island"
    case .home: "Home"
    case .clipboard: "Clipboard"
    case .music: "Music"
    case .widgets: "Widgets"
    case .tray: "File Tray"
    case .swipe: "Swipe between tabs"
    case .rightClick: "Right-click for options"
    case .closed: "The closed island"
    case .done: "You’re all set"
    }
  }

  /// One or two short lines under the title.
  func lines(_ context: IslandTourContext) -> [String] {
    switch self {
    case .open:
      switch (context.floating, context.opensOnHover) {
      case (false, true): return ["Move the pointer to the notch at the top of the screen and rest it there."]
      case (true, true): return ["Move the pointer to the pill at the top of the screen and rest it there."]
      case (false, false): return ["Click the notch at the top of the screen to open it."]
      case (true, false): return ["Click the pill at the top of the screen to open it."]
      }
    case .home:
      return ["Home holds your widgets, with a small player for your music.",
              "To change them, right-click the tab bar and choose Customize Home."]
    case .clipboard:
      return ["This tab holds everything you copied, plus your screenshots.",
              "Press ⌥⇧Space to open it from anywhere."]
    case .music:
      return ["The music note opens the full player, with lyrics and Playing Next.",
              context.hasTrack ? "Swipe on the closed island to skip tracks."
                : "Nothing is playing yet. Play a song and it shows up here."]
    case .widgets:
      return ["The grid tab holds tools like timer, calendar, weather and stats.",
              "Tap a tile to open it right inside the island."]
    case .tray:
      return [context.floating ? "Drag any file onto the island to park it here for later."
                : "Drag any file onto the notch to park it here for later.",
              "Its tab appears while the tray holds files."]
    case .swipe:
      return ["Swipe left or right with two fingers on the island to switch tabs."]
    case .rightClick:
      return ["Right-click the tab bar for options like Customize Home and Settings."]
    case .closed:
      return ["Closed, it shows glances, volume and brightness, and live activities.",
              "Move the pointer to it any time to open it again."]
    case .done:
      return ["Replay this tour any time from Settings → General or the menu bar menu."]
    }
  }

  /// Steps the tour can't show by itself: the user has to try them (Next still skips ahead).
  func waitsForAction(_ context: IslandTourContext) -> Bool {
    self == .open || self == .swipe
  }

  /// What the island shows while this step is up.
  var demo: IslandTourDemo {
    switch self {
    case .open, .closed: .closed
    case .home, .swipe, .rightClick: .page(.home)
    case .clipboard: .page(.clipboard)
    case .music: .page(.music)
    case .widgets: .page(.widgets)
    case .tray: .page(.tray)
    case .done: .none
    }
  }

  var target: IslandTourTarget {
    switch self {
    case .open, .closed: .notch
    case .home: .tab(.home)
    case .clipboard: .tab(.clipboard)
    case .music: .tab(.music)
    case .widgets: .tab(.widgets)
    case .tray: .tab(.tray)
    case .swipe: .islandBody
    case .rightClick: .tabBar
    case .done: .none
    }
  }

  var hold: IslandTourHold {
    switch self {
    case .open, .closed, .done: .none
    case .home, .clipboard, .music, .widgets, .tray, .swipe, .rightClick: .open
    }
  }

  /// Whether going from `old` to `new` is the user doing this step themselves. `old` is nil only for
  /// the first look when the tour starts, so an island that is already open passes the first step.
  /// A page step counts as done when the user taps on to the next step's tab.
  func isCompleted(from old: IslandTourSnapshot?, to new: IslandTourSnapshot) -> Bool {
    switch self {
    case .open:
      return new.expanded && old?.expanded != true
    case .home:
      return arrives(at: .clipboard, from: old, to: new)
    case .clipboard:
      return arrives(at: .music, from: old, to: new)
    case .music:
      return arrives(at: .widgets, from: old, to: new)
    case .swipe:
      guard let old else { return false }
      return old.expanded && new.expanded && old.page != new.page
    case .closed:
      return old?.expanded == false && new.expanded
    case .widgets, .tray, .rightClick, .done:
      return false
    }
  }

  private func arrives(at page: IslandPage, from old: IslandTourSnapshot?, to new: IslandTourSnapshot) -> Bool {
    guard let old else { return false }
    return new.expanded && new.page == page && old.page != page
  }
}

/// One run of the tour: the current step and the last island state it saw.
struct IslandTourSession: Equatable {
  enum Outcome: Equatable { case finished, skipped }

  private(set) var step: IslandTourStep = .open
  private(set) var outcome: Outcome?
  private var last: IslandTourSnapshot?

  var isRunning: Bool { outcome == nil }
  /// 1-based position for the "2 / 10" counter.
  var position: Int { step.rawValue + 1 }
  static var count: Int { IslandTourStep.allCases.count }

  /// Feeds the island's state; returns true when it completed the current step and moved on.
  @discardableResult
  mutating func observe(_ snapshot: IslandTourSnapshot) -> Bool {
    defer { last = snapshot }
    guard isRunning, step.isCompleted(from: last, to: snapshot) else { return false }
    advance()
    return true
  }

  /// The tour itself changed the island (a step's demo): take this as the new baseline, so the
  /// change it made doesn't count as the user doing the step.
  mutating func rebase(_ snapshot: IslandTourSnapshot) {
    last = snapshot
  }

  /// Next: the following step, or finishing on the last one.
  mutating func next() {
    guard isRunning else { return }
    if step == .done { outcome = .finished } else { advance() }
  }

  mutating func back() {
    guard isRunning, let previous = IslandTourStep(rawValue: step.rawValue - 1) else { return }
    step = previous
  }

  mutating func skip() {
    guard isRunning else { return }
    outcome = .skipped
  }

  private mutating func advance() {
    if let following = IslandTourStep(rawValue: step.rawValue + 1) { step = following }
  }
}

/// When the tour may start, and what finishing it records.
enum IslandTourPolicy {
  /// Seconds after launch before a user who finished the introduction long ago gets the tour once.
  static let launchDelay: TimeInterval = 4
  /// Seconds after the introduction window closes before the tour starts.
  static let afterIntroductionDelay: TimeInterval = 1

  static func startsAutomatically(islandEnabled: Bool, introductionDone: Bool, tourDone: Bool) -> Bool {
    islandEnabled && introductionDone && !tourDone
  }

  /// Finishing and skipping both count as done, so the tour never comes back by itself.
  static func record(_ outcome: IslandTourSession.Outcome, in settings: AppSettings) {
    settings.islandTourCompleted = true
  }
}
