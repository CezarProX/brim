// TerminalBuffer.swift
// Brim
//
// A character grid with scrollback that applies `ANSIEvent`s: cursor movement, erase, SGR colors,
// scroll regions, and a simple alternate screen. Value-free of any UI so it can be tested.

import Foundation

/// A terminal color: default, one of the 256 palette entries, or truecolor.
enum TerminalColor: Equatable, Hashable {
  case standard
  case palette(Int)
  case rgb(UInt8, UInt8, UInt8)
}

struct TerminalStyle: Equatable, Hashable {
  var foreground = TerminalColor.standard
  var background = TerminalColor.standard
  var bold = false
  var dim = false
  var italic = false
  var underline = false
  var inverse = false
}

struct TerminalCell: Equatable {
  var character: Character = " "
  var style = TerminalStyle()
}

struct TerminalBuffer {
  private(set) var columns: Int
  private(set) var rows: Int
  private(set) var grid: [[TerminalCell]]
  private(set) var scrollback: [[TerminalCell]] = []
  private(set) var cursorRow = 0
  private(set) var cursorColumn = 0
  private(set) var title = ""
  private(set) var cursorVisible = true
  /// The shell asked for bracketed paste (?2004), so a multi-line paste is held on the line, not run.
  private(set) var bracketedPaste = false
  /// Bumps on every change so views can cheaply notice.
  private(set) var revision = 0
  let scrollbackLimit: Int

  private var style = TerminalStyle()
  private var pendingWrap = false
  private var savedCursor = (row: 0, column: 0)
  private var scrollTop = 0
  private var scrollBottom: Int
  private var primary: (grid: [[TerminalCell]], row: Int, column: Int)?

  init(columns: Int = 80, rows: Int = 12, scrollbackLimit: Int = 2000) {
    self.columns = max(2, columns)
    self.rows = max(1, rows)
    self.scrollbackLimit = scrollbackLimit
    grid = Self.blank(rows: max(1, rows), columns: max(2, columns))
    scrollBottom = max(1, rows) - 1
  }

  var inAlternateScreen: Bool { primary != nil }

  /// Scrollback followed by the live grid.
  var allLines: [[TerminalCell]] { scrollback + grid }

  /// Plain text of the grid row, trailing spaces trimmed.
  func text(row: Int) -> String {
    guard grid.indices.contains(row) else { return "" }
    return String(grid[row].map(\.character)).replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
  }

  /// Everything the terminal holds, scrollback and screen, as plain text without trailing blank lines.
  var fullText: String {
    var lines = allLines.map { line in
      String(line.map(\.character)).replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
    }
    while lines.last?.isEmpty == true { lines.removeLast() }
    return lines.joined(separator: "\n")
  }

  /// True while nothing but (at most) the first prompt line has been written.
  var isFresh: Bool {
    scrollback.isEmpty && (0..<rows).filter { !text(row: $0).isEmpty }.count <= 1
  }

  /// Drops the scrollback; the visible screen stays.
  mutating func clearScrollback() {
    scrollback = []
    revision &+= 1
  }

  var screenText: String { (0..<rows).map { text(row: $0) }.joined(separator: "\n") }

  mutating func apply(_ events: [ANSIEvent]) {
    for event in events { apply(event) }
    revision &+= 1
  }

  mutating func resize(columns newColumns: Int, rows newRows: Int) {
    let newColumns = max(2, newColumns), newRows = max(1, newRows)
    guard newColumns != columns || newRows != rows else { return }
    for index in grid.indices {
      if grid[index].count < newColumns { grid[index] += Array(repeating: TerminalCell(), count: newColumns - grid[index].count) } else {
        grid[index] = Array(grid[index].prefix(newColumns))
      }
    }
    while grid.count > newRows {
      if cursorRow > 0 || grid.count - 1 < cursorRow { scrollback.append(grid.removeFirst()); cursorRow = max(0, cursorRow - 1) } else { grid.removeLast() }
    }
    while grid.count < newRows { grid.append(Array(repeating: TerminalCell(), count: newColumns)) }
    columns = newColumns
    rows = newRows
    scrollTop = 0
    scrollBottom = newRows - 1
    cursorColumn = min(cursorColumn, newColumns - 1)
    cursorRow = min(cursorRow, newRows - 1)
    trimScrollback()
    revision &+= 1
  }

  // MARK: Events

  private mutating func apply(_ event: ANSIEvent) {
    switch event {
    case .text(let character): put(character)
    case .control(let byte): control(byte)
    case .csi(let params, let prefix, let final): csi(params, prefix, final)
    case .escape(let character): escape(character)
    case .osc(let string):
      if string.hasPrefix("0;") || string.hasPrefix("2;") { title = String(string.dropFirst(2).prefix(80)) }
    }
  }

  private mutating func put(_ character: Character) {
    if pendingWrap {
      pendingWrap = false
      cursorColumn = 0
      lineFeed()
    }
    grid[cursorRow][cursorColumn] = TerminalCell(character: character, style: style)
    if cursorColumn == columns - 1 { pendingWrap = true } else { cursorColumn += 1 }
  }

  private mutating func control(_ byte: UInt8) {
    switch byte {
    case 8: cursorColumn = max(0, cursorColumn - 1); pendingWrap = false
    case 9: cursorColumn = min(columns - 1, (cursorColumn / 8 + 1) * 8); pendingWrap = false
    case 10: lineFeed()
    case 13: cursorColumn = 0; pendingWrap = false
    default: break
    }
  }

  private mutating func lineFeed() {
    if cursorRow == scrollBottom { scrollUp(1) } else if cursorRow < rows - 1 { cursorRow += 1 }
  }

  private mutating func scrollUp(_ count: Int) {
    for _ in 0..<count {
      let removed = grid.remove(at: scrollTop)
      if scrollTop == 0 && primary == nil { scrollback.append(removed) }
      grid.insert(Array(repeating: TerminalCell(), count: columns), at: scrollBottom)
    }
    trimScrollback()
  }

  private mutating func scrollDown(_ count: Int) {
    for _ in 0..<count {
      grid.remove(at: scrollBottom)
      grid.insert(Array(repeating: TerminalCell(), count: columns), at: scrollTop)
    }
  }

  private mutating func trimScrollback() {
    if scrollback.count > scrollbackLimit { scrollback.removeFirst(scrollback.count - scrollbackLimit) }
  }

  private mutating func escape(_ character: Character) {
    switch character {
    case "7": savedCursor = (cursorRow, cursorColumn)
    case "8": cursorRow = savedCursor.row; cursorColumn = savedCursor.column; pendingWrap = false
    case "M": if cursorRow == scrollTop { scrollDown(1) } else { cursorRow = max(0, cursorRow - 1) }
    case "D": lineFeed()
    case "E": cursorColumn = 0; lineFeed()
    case "c": self = TerminalBuffer(columns: columns, rows: rows, scrollbackLimit: scrollbackLimit)
    default: break
    }
  }

  private mutating func csi(_ params: [Int], _ prefix: Character?, _ final: Character) {
    pendingWrap = false
    func p(_ index: Int, _ fallback: Int = 1) -> Int {
      params.indices.contains(index) && params[index] > 0 ? params[index] : fallback
    }
    if prefix == "?" { return privateMode(params, set: final == "h", final: final) }
    switch final {
    case "A": cursorRow = max(0, cursorRow - p(0))
    case "B": cursorRow = min(rows - 1, cursorRow + p(0))
    case "C": cursorColumn = min(columns - 1, cursorColumn + p(0))
    case "D": cursorColumn = max(0, cursorColumn - p(0))
    case "E": cursorColumn = 0; cursorRow = min(rows - 1, cursorRow + p(0))
    case "F": cursorColumn = 0; cursorRow = max(0, cursorRow - p(0))
    case "G": cursorColumn = min(columns - 1, p(0) - 1)
    case "d": cursorRow = min(rows - 1, p(0) - 1)
    case "H", "f": cursorRow = min(rows - 1, p(0) - 1); cursorColumn = min(columns - 1, p(1) - 1)
    case "J": eraseDisplay(params.first ?? 0)
    case "K": eraseLine(params.first ?? 0)
    case "L": insertLines(p(0))
    case "M": deleteLines(p(0))
    case "P": deleteCharacters(p(0))
    case "@": insertCharacters(p(0))
    case "X": for column in cursorColumn..<min(columns, cursorColumn + p(0)) { grid[cursorRow][column] = TerminalCell() }
    case "S": scrollUp(p(0))
    case "T": scrollDown(p(0))
    case "m": sgr(params.isEmpty ? [0] : params)
    case "r":
      let top = p(0) - 1, bottom = min(rows - 1, p(1, rows) - 1)
      if top < bottom { scrollTop = top; scrollBottom = bottom }
      cursorRow = 0; cursorColumn = 0
    case "s": savedCursor = (cursorRow, cursorColumn)
    case "u": cursorRow = savedCursor.row; cursorColumn = savedCursor.column
    default: break
    }
  }

  private mutating func privateMode(_ params: [Int], set: Bool, final: Character) {
    guard final == "h" || final == "l" else { return }
    for mode in params {
      switch mode {
      case 25: cursorVisible = set
      case 2004: bracketedPaste = set
      case 1049, 47, 1047: set ? enterAlternateScreen() : leaveAlternateScreen()
      default: break
      }
    }
  }

  private mutating func enterAlternateScreen() {
    guard primary == nil else { return }
    primary = (grid, cursorRow, cursorColumn)
    grid = Self.blank(rows: rows, columns: columns)
    cursorRow = 0; cursorColumn = 0
  }

  private mutating func leaveAlternateScreen() {
    guard let saved = primary else { return }
    grid = saved.grid
    cursorRow = min(saved.row, rows - 1); cursorColumn = min(saved.column, columns - 1)
    primary = nil
    scrollTop = 0; scrollBottom = rows - 1
  }

  private mutating func eraseDisplay(_ mode: Int) {
    switch mode {
    case 0:
      eraseLine(0)
      for row in (cursorRow + 1)..<max(cursorRow + 1, rows) { grid[row] = Array(repeating: TerminalCell(), count: columns) }
    case 1:
      eraseLine(1)
      for row in 0..<cursorRow { grid[row] = Array(repeating: TerminalCell(), count: columns) }
    default:
      grid = Self.blank(rows: rows, columns: columns)
    }
  }

  private mutating func eraseLine(_ mode: Int) {
    let range: Range<Int>
    switch mode {
    case 0: range = cursorColumn..<columns
    case 1: range = 0..<(cursorColumn + 1)
    default: range = 0..<columns
    }
    for column in range { grid[cursorRow][column] = TerminalCell(character: " ", style: TerminalStyle(background: style.background)) }
  }

  private mutating func insertLines(_ count: Int) {
    guard cursorRow >= scrollTop, cursorRow <= scrollBottom else { return }
    for _ in 0..<min(count, scrollBottom - cursorRow + 1) {
      grid.remove(at: scrollBottom)
      grid.insert(Array(repeating: TerminalCell(), count: columns), at: cursorRow)
    }
  }

  private mutating func deleteLines(_ count: Int) {
    guard cursorRow >= scrollTop, cursorRow <= scrollBottom else { return }
    for _ in 0..<min(count, scrollBottom - cursorRow + 1) {
      grid.remove(at: cursorRow)
      grid.insert(Array(repeating: TerminalCell(), count: columns), at: scrollBottom)
    }
  }

  private mutating func deleteCharacters(_ count: Int) {
    let n = min(count, columns - cursorColumn)
    grid[cursorRow].removeSubrange(cursorColumn..<(cursorColumn + n))
    grid[cursorRow] += Array(repeating: TerminalCell(), count: n)
  }

  private mutating func insertCharacters(_ count: Int) {
    let n = min(count, columns - cursorColumn)
    grid[cursorRow].insert(contentsOf: Array(repeating: TerminalCell(), count: n), at: cursorColumn)
    grid[cursorRow].removeLast(n)
  }

  // MARK: SGR

  private mutating func sgr(_ params: [Int]) {
    var index = 0
    while index < params.count {
      let code = params[index]
      switch code {
      case 0: style = TerminalStyle()
      case 1: style.bold = true
      case 2: style.dim = true
      case 3: style.italic = true
      case 4: style.underline = true
      case 7: style.inverse = true
      case 22: style.bold = false; style.dim = false
      case 23: style.italic = false
      case 24: style.underline = false
      case 27: style.inverse = false
      case 30...37: style.foreground = .palette(code - 30)
      case 40...47: style.background = .palette(code - 40)
      case 90...97: style.foreground = .palette(code - 90 + 8)
      case 100...107: style.background = .palette(code - 100 + 8)
      case 39: style.foreground = .standard
      case 49: style.background = .standard
      case 38, 48:
        if let (color, used) = Self.extendedColor(params, from: index + 1) {
          if code == 38 { style.foreground = color } else { style.background = color }
          index += used
        }
      default: break
      }
      index += 1
    }
  }

  private static func extendedColor(_ params: [Int], from start: Int) -> (TerminalColor, Int)? {
    guard params.indices.contains(start) else { return nil }
    if params[start] == 5, params.indices.contains(start + 1) { return (.palette(min(255, params[start + 1])), 2) }
    if params[start] == 2, params.indices.contains(start + 3) {
      let clamp = { UInt8(min(255, max(0, $0))) }
      return (.rgb(clamp(params[start + 1]), clamp(params[start + 2]), clamp(params[start + 3])), 4)
    }
    return nil
  }

  private static func blank(rows: Int, columns: Int) -> [[TerminalCell]] {
    Array(repeating: Array(repeating: TerminalCell(), count: columns), count: rows)
  }
}
