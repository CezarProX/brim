import SwiftUI

/// The pages of the first-run tour, in order.
enum OnboardingPage: Int, CaseIterable, Identifiable {
  case welcome, tray, transform, clipboard, player, glass, huds, live, replies, lockScreen, widgets, glances, permissions, almostThere, finish

  var id: Int { rawValue }

  var title: String {
    switch self {
    case .welcome: "Meet Brim."
    case .tray: "Keep files within reach."
    case .transform: "Transform any file."
    case .clipboard: "Never lose what you copied."
    case .player: "Your music, one glance up."
    case .glass: "Liquid Glass, your way."
    case .huds: "Live Activities."
    case .live: "Downloads and meetings, live."
    case .replies: "Reply from the notch."
    case .lockScreen: "A Lock Screen that moves."
    case .widgets: "Widgets and Droplets."
    case .glances: "Glances beside the island."
    case .permissions: "A few permissions."
    case .almostThere: "Almost there."
    case .finish: "You’re all set."
    }
  }

  var subtitle: String {
    switch self {
    case .welcome: "Screenshots, files, music and system status, living in your notch and menu bar."
    case .tray: "Drag files to the top of your screen and they wait there until you need them. Drag them into any app, or AirDrop them from there."
    case .transform: "Drop files on Transform in the island to compress, convert, resize or trim them. Pick where results go here, or in Settings."
    case .clipboard: "Brim keeps everything you copy, from text and links to images and colors. Bring any of it back with one shortcut."
    case .player: "Playback, lyrics and a Playing Next queue in the island, or in a floating glass player. Swipe on the cover to skip."
    case .glass: "Tinted glass keeps text readable on any wallpaper. Prefer it clear? Pick it here, or fine-tune it in Settings, Theming."
    case .huds: "Volume, brightness, keyboard backlight and more arrive as calm HUDs that grow into a card when you hover."
    case .live: "Watch a download finish with a ring and a countdown. See your next meeting, and join it with one click."
    case .replies: "Answer WhatsApp and Telegram right in the island. Scan the code once with your phone, or skip and link later from any message."
    case .lockScreen: "Now Playing, timers and weather on the lock screen, with the same glass look and moving album art."
    case .widgets: "CPU, battery, weather, notes and more. One tap on a tile opens it right inside the island."
    case .glances: "The closed island shows a clock, battery, timer or your next event on either side, only when there is something to say."
    case .permissions: "Brim asks only for what a feature needs. Everything stays on your Mac."
    case .almostThere: "Choose whether Brim opens when you log in. You can change this any time in Settings."
    case .finish: "Open the Command Center from the menu bar whenever you like. You can replay this tour from Settings, About."
    }
  }

  var buttonTitle: String { self == .finish ? "Start using Brim" : "Continue" }

  var isLast: Bool { self == OnboardingPage.allCases.last }

  /// The pages a tour walks through. The reply page only shows when there is something to link.
  static func tour(offeringReplies: Bool) -> [OnboardingPage] {
    allCases.filter { $0 != .replies || offeringReplies }
  }

  /// How many glass option rows sit under the copy; those pages lift the copy to make room.
  var optionRowCount: Int {
    switch self {
    case .transform, .glass, .replies: 2
    case .almostThere: 1
    default: 0
    }
  }

  /// What hangs from the top of the window above the copy.
  enum Hero: Equatable {
    /// The island, open, at this size.
    case island(CGSize)
    /// A MacBook display seen from the front, with the real notch.
    case screen
    /// No island: the content brings its own panel.
    case panel
  }

  var hero: Hero {
    switch self {
    case .welcome: .island(CGSize(width: 400, height: 168))
    case .tray: .island(CGSize(width: IslandPageLayout.trayWidth, height: 36 + IslandPageLayout.trayHeight(count: 4)))
    case .transform: .island(CGSize(width: TransformPanelView.preferredWidth, height: 396))
    case .clipboard: .island(CGSize(width: 612, height: 238))
    case .player, .glass: .island(CGSize(width: MusicPlayerCard.preferredSize(showsQueue: true, topInset: 36).width, height: 195))
    case .live: .island(CGSize(width: 470, height: 214))
    case .replies: .island(CGSize(width: 404, height: 36 + ReplyLinkPanel.height + 14))
    case .widgets: .island(CGSize(width: IslandPageLayout.widgetsWidth, height: 36 + IslandPageLayout.widgetsHeight(tiles: 8)))
    case .almostThere: .island(CGSize(width: 250, height: 36))
    case .lockScreen, .glances: .screen
    case .huds, .permissions, .finish: .panel
    }
  }
}

/// Fixed measurements of the tour window, in points (the window is 800 by 760).
enum OnboardingMetrics {
  static let size = CGSize(width: 800, height: 760)
  static let cornerRadius: CGFloat = 30
  static let band: CGFloat = 32
  static let buttonSize = CGSize(width: 220, height: 42)
  static let buttonCenterY: CGFloat = 717
  static let rowWidth: CGFloat = 480
  static let rowHeight: CGFloat = 40
  static let rowPitch: CGFloat = 48
  static let rowsTop: CGFloat = 573

  static func dotsY(rows: Bool) -> CGFloat { rows ? 451 : 551 }
  static func titleY(rows: Bool) -> CGFloat { dotsY(rows: rows) + 48 }
  static func subtitleTop(rows: Bool) -> CGFloat { titleY(rows: rows) + 24 }
}
