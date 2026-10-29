import Foundation

/// A tile with its page and grid position.
struct PlacedTile: Equatable, Identifiable {
  let placement: TilePlacement
  let page: Int
  let column: Int
  let row: Int
  var id: String { placement.id }
}

/// Pure layout rules for the Command Center: pagination, edit operations, presets and the
/// persisted string form. Every operation returns a new array and never touches the input.
enum CommandCenterLayout {
  static let columns = 4
  static let rows = 3

  // MARK: Pagination

  /// First-fit packing onto 4x3 pages, keeping list order. A tile that fits no existing page opens a new one.
  static func paginate(_ placements: [TilePlacement]) -> [[PlacedTile]] {
    var pages: [[PlacedTile]] = []
    var grids: [[[Bool]]] = []
    for placement in placements {
      let size = placement.size
      var spot: (page: Int, column: Int, row: Int)?
      for page in grids.indices {
        if let free = firstFree(in: grids[page], size: size) { spot = (page, free.column, free.row); break }
      }
      if spot == nil {
        grids.append(Array(repeating: Array(repeating: false, count: columns), count: rows))
        pages.append([])
        let free = firstFree(in: grids[grids.count - 1], size: size) ?? (0, 0)
        spot = (grids.count - 1, free.column, free.row)
      }
      guard let spot else { continue }
      for r in spot.row..<(spot.row + size.rows) {
        for c in spot.column..<(spot.column + size.columns) { grids[spot.page][r][c] = true }
      }
      pages[spot.page].append(PlacedTile(placement: placement, page: spot.page, column: spot.column, row: spot.row))
    }
    return pages
  }

  private static func firstFree(in grid: [[Bool]], size: TileSize) -> (column: Int, row: Int)? {
    guard size.columns <= columns, size.rows <= rows else { return nil }
    for row in 0...(rows - size.rows) {
      for column in 0...(columns - size.columns) {
        let blocked = (row..<(row + size.rows)).contains { r in
          (column..<(column + size.columns)).contains { grid[r][$0] }
        }
        if !blocked { return (column, row) }
      }
    }
    return nil
  }

  static func pageCount(_ placements: [TilePlacement]) -> Int { max(1, paginate(placements).count) }

  /// The page to open on, given the start-page setting and the last page used.
  static func startPage(_ mode: CommandCenterStartPage, lastUsed: Int, pageCount: Int) -> Int {
    mode == .first ? 0 : min(max(0, lastUsed), max(0, pageCount - 1))
  }

  // MARK: Edit operations

  static func adding(_ kind: TileKind, to placements: [TilePlacement]) -> [TilePlacement] {
    placements.contains { $0.kind == kind } ? placements : placements + [TilePlacement(kind)]
  }

  static func removing(_ kind: TileKind, from placements: [TilePlacement]) -> [TilePlacement] {
    placements.filter { $0.kind != kind }
  }

  /// Moves `kind` so it sits where `target` is now (drag-reorder semantics).
  static func moving(_ kind: TileKind, onto target: TileKind, in placements: [TilePlacement]) -> [TilePlacement] {
    guard kind != target, let from = placements.firstIndex(where: { $0.kind == kind }),
      let to = placements.firstIndex(where: { $0.kind == target }) else { return placements }
    var next = placements
    let moved = next.remove(at: from)
    next.insert(moved, at: to)
    return next
  }

  /// Shifts one tile a step earlier (-1) or later (+1), clamped to the list.
  static func shifting(_ kind: TileKind, by offset: Int, in placements: [TilePlacement]) -> [TilePlacement] {
    guard let from = placements.firstIndex(where: { $0.kind == kind }) else { return placements }
    let to = min(max(0, from + offset), placements.count - 1)
    guard to != from else { return placements }
    var next = placements
    next.insert(next.remove(at: from), at: to)
    return next
  }

  /// Steps to the next size the tile allows, wrapping around.
  static func cyclingSize(_ kind: TileKind, in placements: [TilePlacement]) -> [TilePlacement] {
    placements.map { placement in
      guard placement.kind == kind, let index = kind.allowedSizes.firstIndex(of: placement.size) else { return placement }
      var copy = placement
      copy.size = kind.allowedSizes[(index + 1) % kind.allowedSizes.count]
      return copy
    }
  }

  static func available(excluding placements: [TilePlacement]) -> [TileKind] {
    let used = Set(placements.map(\.kind))
    return TileKind.allCases.filter { !used.contains($0) }
  }

  // MARK: Presets

  struct Preset: Identifiable, Equatable {
    let id: String
    let title: String
    let placements: [TilePlacement]
  }

  static let presets: [Preset] = [
    Preset(id: "default", title: "Balanced", placements: [
      TilePlacement(.nowPlaying, .hero), TilePlacement(.clipboard), TilePlacement(.captureArea),
      TilePlacement(.ocr), TilePlacement(.transform), TilePlacement(.darkMode), TilePlacement(.stayAwake),
      TilePlacement(.desktopIcons), TilePlacement(.hiddenFiles), TilePlacement(.islandVisibility),
      TilePlacement(.upcoming, .wide), TilePlacement(.cpu), TilePlacement(.memory), TilePlacement(.disk),
      TilePlacement(.battery), TilePlacement(.network, .wide), TilePlacement(.settings),
    ]),
    Preset(id: "capture", title: "Capture first", placements: [
      TilePlacement(.captureArea, .wide), TilePlacement(.captureWindow), TilePlacement(.captureFullscreen),
      TilePlacement(.ocr), TilePlacement(.colorPicker), TilePlacement(.history), TilePlacement(.clipboard),
      TilePlacement(.transform), TilePlacement(.nowPlaying, .wide), TilePlacement(.settings),
    ]),
    Preset(id: "system", title: "System", placements: [
      TilePlacement(.cpu), TilePlacement(.memory), TilePlacement(.disk), TilePlacement(.battery),
      TilePlacement(.network, .wide), TilePlacement(.stayAwake), TilePlacement(.darkMode),
      TilePlacement(.desktopIcons), TilePlacement(.hiddenFiles), TilePlacement(.islandVisibility),
      TilePlacement(.upcoming, .wide), TilePlacement(.settings),
    ]),
    Preset(id: "minimal", title: "Minimal", placements: [
      TilePlacement(.nowPlaying, .hero), TilePlacement(.captureArea), TilePlacement(.clipboard),
      TilePlacement(.stayAwake), TilePlacement(.settings),
    ]),
  ]

  static var defaultPlacements: [TilePlacement] { presets[0].placements }

  // MARK: Persistence

  static func serialize(_ placements: [TilePlacement]) -> String {
    placements.map { "\($0.kind.rawValue)@\($0.size.rawValue)" }.joined(separator: ",")
  }

  /// Unknown tiles are dropped, repeats collapse to the first, and a size the tile can't take falls back to its default.
  /// Garbage or empty input yields the default layout; an explicit empty layout is stored as "-".
  static func parse(_ text: String?) -> [TilePlacement] {
    guard let text, !text.isEmpty else { return defaultPlacements }
    if text == "-" { return [] }
    var seen = Set<TileKind>()
    var result: [TilePlacement] = []
    for part in text.split(separator: ",") {
      let bits = part.split(separator: "@", omittingEmptySubsequences: false).map(String.init)
      guard let kind = TileKind(rawValue: bits[0]), seen.insert(kind).inserted else { continue }
      result.append(TilePlacement(kind, bits.count > 1 ? TileSize(rawValue: bits[1]) : nil))
    }
    return result.isEmpty ? defaultPlacements : result
  }

  static func storageString(_ placements: [TilePlacement]) -> String {
    placements.isEmpty ? "-" : serialize(placements)
  }
}
