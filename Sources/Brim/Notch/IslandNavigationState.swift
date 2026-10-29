import SwiftUI

/// Where the open island is: a page, and on the Widgets page the widget that is open.
/// It maps onto `NotchPresentation`'s flags, which the controller also sets (the clipboard
/// hotkey opens the Clipboard widget; a file drop opens the Tray).
struct IslandNavigation: Equatable {
  var library = false
  var clipboard = false
  var activities = false
  var calendar = false
  var widget: IslandWidgetTile?
  var music = false
  var messages = false

  var page: IslandPage {
    if messages { return .messages }
    if library && clipboard { return .clipboard }
    if music { return .music }
    if activities || calendar { return .widgets }
    return library ? .tray : .home
  }

  /// The widget open on the Widgets page, nil while the grid shows.
  var openedWidget: IslandWidgetTile? {
    if calendar { return .calendar }
    if library && clipboard { return nil }
    return activities ? widget : nil
  }

  static func showing(_ page: IslandPage) -> IslandNavigation {
    switch page {
    case .home: IslandNavigation()
    case .clipboard: IslandNavigation(library: true, clipboard: true)
    case .tray: IslandNavigation(library: true)
    case .music: IslandNavigation(music: true)
    case .widgets: IslandNavigation(activities: true)
    case .messages: IslandNavigation(messages: true)
    }
  }

  static func opening(_ widget: IslandWidgetTile?) -> IslandNavigation {
    switch widget {
    case .clipboard: IslandNavigation(library: true, clipboard: true)
    case .calendar: IslandNavigation(calendar: true)
    // Now Playing is the Music tab's player; there is no second, weaker one in the grid.
    case .nowPlaying: IslandNavigation(music: true)
    default: IslandNavigation(activities: true, widget: widget)
    }
  }
}

extension NotchPresentation {
  var navigation: IslandNavigation {
    IslandNavigation(
      library: isShowingLibrary, clipboard: openedFromClipboard, activities: isShowingActivities,
      calendar: isShowingCalendar, widget: openWidget, music: isShowingMusic, messages: isShowingMessages)
  }

  /// Applies a destination; callers wrap this in the layout spring.
  func navigate(to next: IslandNavigation) {
    isShowingLibrary = next.library
    openedFromClipboard = next.clipboard
    isShowingActivities = next.activities
    isShowingCalendar = next.calendar
    openWidget = next.widget
    isShowingMusic = next.music
    isShowingMessages = next.messages
    trayTab = next.clipboard ? .clipboard : .files
    homeTapped = next.page == .home
    // The output picker belongs to the player on the Music page.
    if next.page != .music { isPresentingAudioOutputs = false }
    if next.page == .home { selectedActivity = nil }
  }

  /// Reopens on the page and widget the island closed on, so leaving the Clipboard (or the
  /// Widgets grid) and coming back finds it still there. With nothing remembered yet it opens on
  /// Music while the closed island shows the song (as the player-first Home used to), else on Home.
  /// Anything that opened the island onto something specific (the clipboard hotkey, a drop, a
  /// notification card) wins.
  func restorePage(_ remembered: IslandNavigation?, closedOnMusic: Bool = false) {
    guard !homeTapped, !isShowingLibrary, !isShowingActivities, !isShowingCalendar, !isShowingMusic, !isShowingMessages,
          selectedActivity == nil,
          !expandedForNotification, !isShowingDropTargets, convertURLs.isEmpty, localSendURLs.isEmpty
    else { return }
    if let remembered {
      if remembered.page != .home { navigate(to: remembered) }
    } else if closedOnMusic {
      navigate(to: .showing(.music))
    }
  }
}

/// Sizes of the Tray and Widgets pages
/// (tray ≈ 500 wide, widgets ≈ 556 wide, icons 64–68 pt, two widget rows ≈ 320 pt tall).
enum IslandPageLayout {
  static let trayWidth: CGFloat = 500
  static let widgetsWidth: CGFloat = 556
  /// The open notch shape flares into a shoulder this wide on each side (see NotchSurfaceShape),
  /// so content laid out edge to edge needs this much extra width to keep its own side inset.
  static let openShoulder: CGFloat = 12

  /// Height under the camera band for the tray: one row of files, two when they overflow.
  static func trayHeight(count: Int) -> CGFloat {
    guard count > 0 else { return 150 }
    let rows = min(FileTrayGrid.visibleRows, (count + FileTrayGrid.columns - 1) / FileTrayGrid.columns)
    return FileTrayGrid.topPadding + CGFloat(rows) * FileTrayGrid.rowHeight
      + CGFloat(rows - 1) * FileTrayGrid.rowSpacing + FileTrayGrid.bottomPadding
  }

  /// Height under the camera band for the Clipboard page: the old Clipboard widget without its back row.
  static let clipboardHeight: CGFloat = IslandWidgetTile.clipboard.openHeight - 36

  /// Height under the camera band for the widget grid: one or two rows of icons visible.
  static func widgetsHeight(tiles: Int) -> CGFloat {
    let rows = min(2, max(1, (tiles + IslandWidgetGrid.columns - 1) / IslandWidgetGrid.columns))
    return IslandWidgetGrid.topPadding + CGFloat(rows) * IslandWidgetGrid.tileHeight
      + CGFloat(rows - 1) * IslandWidgetGrid.rowSpacing + IslandWidgetGrid.bottomPadding
  }
}

/// The widget grid: four 115-pt columns of 68-pt icons, rows 131 pt apart.
enum IslandWidgetGrid {
  static let columns = 4
  static let columnWidth: CGFloat = 115
  static let iconSize: CGFloat = 66
  static let labelGap: CGFloat = 13
  static let tileHeight: CGFloat = 100
  static let rowSpacing: CGFloat = 31
  static let topPadding: CGFloat = 28
  static let bottomPadding: CGFloat = 26
  /// Two full rows per page, the height the island shows.
  static let tilesPerPage = columns * 2

  static func pages<Tile>(of tiles: [Tile]) -> [[Tile]] {
    stride(from: 0, to: tiles.count, by: tilesPerPage).map { Array(tiles[$0..<min($0 + tilesPerPage, tiles.count)]) }
  }
}

/// The file tray grid: 107-pt columns of 64-pt thumbnails with names beneath.
enum FileTrayGrid {
  static let columns = 4
  static let columnWidth: CGFloat = 107
  static let thumbnail: CGFloat = 64
  /// Images and movies fill a landscape card instead of shrinking into the square.
  static let mediaWidth: CGFloat = 96
  static let rowHeight: CGFloat = 100
  static let rowSpacing: CGFloat = 12
  static let visibleRows = 2
  static let topPadding: CGFloat = 30
  static let bottomPadding: CGFloat = 30
}
