import CoreGraphics

/// The two Home widget sizes, as on an iPhone: a square small and a medium two smalls (plus the gap) wide.
enum HomeWidgetSize: String, CaseIterable, Codable, Comparable {
  case small, medium

  /// Grid units the size takes in the Home row.
  var units: Int { self == .small ? 1 : 2 }

  var width: CGFloat { HomeWidgetGrid.width(units: units) }

  static func < (lhs: Self, rhs: Self) -> Bool { lhs.units < rhs.units }
}

extension HomeWidget {
  /// The sizes this widget is designed for, smallest first. Each size has its own layout.
  var sizes: [HomeWidgetSize] {
    switch self {
    case .lyrics: [.medium]
    case .awake: [.small]
    default: [.small, .medium]
    }
  }

  /// The size a widget takes when it is added from the dock.
  var defaultSize: HomeWidgetSize {
    switch self {
    case .media, .captures, .notes, .batteries, .weather, .lyrics, .stats: .medium
    case .clock, .timer, .agenda, .awake: .small
    }
  }

  func supports(_ size: HomeWidgetSize) -> Bool { sizes.contains(size) }
}

/// One widget on the Home row with the size the user chose.
struct HomeWidgetItem: Hashable, Identifiable {
  let widget: HomeWidget
  var size: HomeWidgetSize
  var id: HomeWidget { widget }

  init(_ widget: HomeWidget, _ size: HomeWidgetSize? = nil) {
    self.widget = widget
    let wanted = size ?? widget.defaultSize
    self.size = widget.supports(wanted) ? wanted : widget.defaultSize
  }

  /// Saved as the bare widget name at its default size (the format before sizes existed),
  /// or `name:size` otherwise.
  var stored: String { size == widget.defaultSize ? widget.rawValue : "\(widget.rawValue):\(size.rawValue)" }

  init?(stored: String) {
    let parts = stored.split(separator: ":", maxSplits: 1).map(String.init)
    guard let widget = parts.first.flatMap(HomeWidget.init(rawValue:)) else { return nil }
    self.init(widget, parts.count > 1 ? HomeWidgetSize(rawValue: parts[1]) : nil)
  }
}

/// The Home grid's geometry: one row of up to four units per page, at most two pages.
/// Every width here is exact, so the island is always built around what it shows.
enum HomeWidgetGrid {
  /// A small widget's side; the row's height. Includes the card's own padding.
  static let unit: CGFloat = 140
  static let gap: CGFloat = 12
  static let unitsPerPage = 4
  static let maxPages = 2
  /// The most widgets Home can hold (every one small).
  static var maxWidgets: Int { unitsPerPage * maxPages }
  /// A lone small widget still gets an island two units wide, so it never reads as a sliver.
  static let minimumUnits = 2

  static func width(units: Int) -> CGFloat {
    units <= 0 ? 0 : CGFloat(units) * unit + CGFloat(units - 1) * gap
  }

  static func units(_ items: [HomeWidgetItem]) -> Int { items.reduce(0) { $0 + $1.size.units } }

  /// Fills pages in order; a widget that does not fit what is left of a page starts the next one.
  static func pages(_ items: [HomeWidgetItem]) -> [[HomeWidgetItem]] {
    var pages: [[HomeWidgetItem]] = []
    var current: [HomeWidgetItem] = []
    for item in items {
      if units(current) + item.size.units > unitsPerPage {
        pages.append(current)
        current = []
      }
      current.append(item)
    }
    if !current.isEmpty { pages.append(current) }
    return pages
  }

  static func fits(_ items: [HomeWidgetItem]) -> Bool { pages(items).count <= maxPages }

  /// Keeps what fits, in order: a widget too big for the room left shrinks to a smaller size it
  /// supports, or is dropped. Used for saved layouts from before sizes existed (up to six wide widgets).
  static func fitted(_ items: [HomeWidgetItem]) -> [HomeWidgetItem] {
    var kept: [HomeWidgetItem] = []
    var seen = Set<HomeWidget>()
    for item in items where !seen.contains(item.widget) {
      let candidates = [item.size] + item.widget.sizes.filter { $0 < item.size }.reversed()
      if let size = candidates.first(where: { fits(kept + [HomeWidgetItem(item.widget, $0)]) }) {
        kept.append(HomeWidgetItem(item.widget, size))
        seen.insert(item.widget)
      }
    }
    return kept
  }

  /// Width of the grid itself. Editing always shows all four units, so there is room to drop.
  static func gridWidth(_ items: [HomeWidgetItem], editing: Bool) -> CGFloat {
    if editing { return width(units: unitsPerPage) }
    let widest = pages(items).map(units).max() ?? 0
    return width(units: max(minimumUnits, widest))
  }
}
