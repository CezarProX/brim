import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Widgets that sit side by side on the Home shelf.
enum HomeWidget: String, CaseIterable, Identifiable, Codable {
  case media, clock, captures, timer, notes, stats, agenda, batteries, awake, weather, lyrics
  var id: String { rawValue }

  var title: String {
    switch self {
    case .media: "Media"
    case .clock: "Clock"
    case .captures: "Captures"
    case .timer: "Timer"
    case .notes: "Notes"
    case .stats: "Stats"
    case .agenda: "Calendar"
    case .batteries: "Batteries"
    case .awake: "High Alert"
    case .weather: "Weather"
    case .lyrics: "Lyrics"
    }
  }

  var symbol: String {
    switch self {
    case .media: "music.note"
    case .clock: "clock.fill"
    case .captures: "camera.viewfinder"
    case .timer: "timer"
    case .notes: "note.text"
    case .stats: "gauge.with.dots.needle.33percent"
    case .agenda: "calendar"
    case .batteries: "battery.100percent"
    case .awake: "cup.and.saucer.fill"
    case .weather: "cloud.sun.fill"
    case .lyrics: "quote.bubble.fill"
    }
  }

  /// Legacy dock tile colors, kept only until the edit dock draws `HomeWidgetIcon` everywhere.
  /// The art itself lives in `HomeWidget.icon` (Icons/FeatureIconCatalog.swift).
  var gradient: [Color] { [icon.art.top, icon.art.bottom] }

  var glyphColor: Color { .white }
}

/// The Home layout: widgets in the user's order, each small or medium, in pages of four units.
@MainActor
final class HomeWidgetStore: ObservableObject {
  static let shared = HomeWidgetStore()
  /// Side padding around the grid inside the island (half on each side).
  static let horizontalPadding: CGFloat = 40
  static var spacing: CGFloat { HomeWidgetGrid.gap }
  /// Height of the widget row itself: one grid unit.
  static var rowHeight: CGFloat { HomeWidgetGrid.unit }
  /// Room above the row and under the page dots inside the island.
  static let topPadding: CGFloat = 10
  static let bottomPadding: CGFloat = 22
  /// The icon dock and its buttons while editing.
  static let dockHeight: CGFloat = 70
  /// Room around the row while editing, for the remove badges, resize handles, outlines and the wobble.
  static let editMargin: CGFloat = 16
  /// What editing adds to the shelf's height: the dock plus the margin above the row.
  static let editingExtraHeight: CGFloat = dockHeight + editMargin
  @Published private(set) var items: [HomeWidgetItem]
  @Published var isEditing = false
  /// The page in view when the widgets overflow one row.
  @Published var page = 0
  private let persist: ([HomeWidgetItem]) -> Void
  private let scrollMode: () -> WidgetScrollMode

  init(
    items: [HomeWidgetItem],
    persist: @escaping ([HomeWidgetItem]) -> Void = { AppSettings.shared.homeWidgets = $0.map(\.stored) },
    scrollMode: @escaping () -> WidgetScrollMode = { AppSettings.shared.widgetScrollMode }
  ) {
    self.items = HomeWidgetGrid.fitted(items)
    self.persist = persist
    self.scrollMode = scrollMode
  }

  /// Widgets at their default sizes, or the saved layout (older saves without sizes get defaults).
  convenience init(
    widgets: [HomeWidget]? = nil,
    persist: @escaping ([HomeWidgetItem]) -> Void = { AppSettings.shared.homeWidgets = $0.map(\.stored) },
    scrollMode: @escaping () -> WidgetScrollMode = { AppSettings.shared.widgetScrollMode }
  ) {
    let items = widgets.map { $0.map { HomeWidgetItem($0) } }
      ?? AppSettings.shared.homeWidgets.compactMap(HomeWidgetItem.init(stored:))
    self.init(items: items, persist: persist, scrollMode: scrollMode)
  }

  var widgets: [HomeWidget] { items.map(\.widget) }

  /// What the Home shelf shows. Media is a widget like any other: with nothing playing it is the
  /// idle "Not playing" card.
  var shelfWidgets: [HomeWidget] { widgets }

  /// Whether Home shows the idle player card when nothing plays (the user may remove Media).
  var showsIdlePlayer: Bool { widgets.contains(.media) }

  func size(of widget: HomeWidget) -> HomeWidgetSize? { items.first { $0.widget == widget }?.size }

  /// The widgets in pages of four units (a medium that does not fit a page's last unit starts the next).
  var pages: [[HomeWidgetItem]] { HomeWidgetGrid.pages(items) }

  /// Automatic and "one row" page sideways; "two rows" pages up and down.
  var pagesVertically: Bool { scrollMode() == .twoRows }

  /// Width of the grid: the widest page, or all four units while editing.
  var gridWidth: CGFloat { HomeWidgetGrid.gridWidth(items, editing: isEditing) }

  /// Island content width for the shelf: the grid, its side padding, and the edit margins.
  var shelfWidth: CGFloat {
    gridWidth + Self.horizontalPadding + (isEditing ? 2 * Self.editMargin : 0)
  }

  /// While editing more than one page, the page dots get their own strip between the grid and
  /// the dock, clear of the resize handles.
  static let editingDotsHeight: CGFloat = 14
  var editingDotsReserve: CGFloat { isEditing && pages.count > 1 ? Self.editingDotsHeight : 0 }

  /// Content height for the shelf inside the island, below the notch band.
  var shelfHeight: CGFloat {
    Self.topPadding + Self.rowHeight + Self.bottomPadding + (isEditing ? Self.editingExtraHeight : 0)
      + editingDotsReserve
  }

  /// The size a widget would be added at: its default, or a smaller one it supports when only that fits.
  func addableSize(_ widget: HomeWidget) -> HomeWidgetSize? {
    guard !widgets.contains(widget) else { return nil }
    let candidates = [widget.defaultSize] + widget.sizes.filter { $0 < widget.defaultSize }.reversed()
    return candidates.first { HomeWidgetGrid.fits(items + [HomeWidgetItem(widget, $0)]) }
  }

  func canAdd(_ widget: HomeWidget) -> Bool { addableSize(widget) != nil }

  /// Whether a widget on the shelf can switch to `size` without overflowing the pages.
  func canResize(_ widget: HomeWidget, to size: HomeWidgetSize) -> Bool {
    guard widget.supports(size), let index = items.firstIndex(where: { $0.widget == widget }) else { return false }
    var next = items
    next[index] = HomeWidgetItem(widget, size)
    return HomeWidgetGrid.fits(next)
  }

  func toggle(_ widget: HomeWidget) {
    if widgets.contains(widget) {
      save(items.filter { $0.widget != widget })
    } else if let size = addableSize(widget) {
      save(items + [HomeWidgetItem(widget, size)])
    }
  }

  func move(_ widget: HomeWidget, before target: HomeWidget) {
    guard widget != target, let item = items.first(where: { $0.widget == widget }) else { return }
    var next = items.filter { $0.widget != widget }
    let to = next.firstIndex { $0.widget == target } ?? next.endIndex
    next.insert(item, at: to)
    save(next)
  }

  /// Moves a widget to `index` among the others, or adds it there at its default size (dropped
  /// from the dock) when there is room. The index counts the widgets other than this one.
  /// With `keepingPage`, a move that would push the widget onto another page is ignored, so a
  /// widget being dragged never leaves the page under the pointer (its view, and the drag, would end).
  func place(_ widget: HomeWidget, at index: Int, keepingPage page: Int? = nil) {
    let existing = items.first { $0.widget == widget }
    guard let item = existing ?? addableSize(widget).map({ HomeWidgetItem(widget, $0) }) else { return }
    var next = items.filter { $0.widget != widget }
    next.insert(item, at: min(max(0, index), next.count))
    guard next != items else { return }
    if let page {
      let pages = HomeWidgetGrid.pages(next)
      guard page < pages.count, pages[page].contains(where: { $0.widget == widget }) else { return }
    }
    save(next)
  }

  /// Resizes a widget in place, if it supports the size and the pages still hold everything.
  func setSize(_ widget: HomeWidget, _ size: HomeWidgetSize) {
    guard canResize(widget, to: size), let index = items.firstIndex(where: { $0.widget == widget }),
      items[index].size != size
    else { return }
    var next = items
    next[index] = HomeWidgetItem(widget, size)
    save(next)
  }

  /// Puts back an earlier layout, as Cancel does.
  func restore(_ earlier: [HomeWidgetItem]) { save(HomeWidgetGrid.fitted(earlier)) }

  /// Saves only layouts that fit; anything that would need a third page is refused.
  private func save(_ next: [HomeWidgetItem]) {
    guard HomeWidgetGrid.fits(next) else { return }
    items = next
    page = min(page, max(0, pages.count - 1))
    persist(next)
  }
}
