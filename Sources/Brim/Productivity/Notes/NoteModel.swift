import Foundation

/// What a line of a note is. Notes stay Markdown on disk; this is the editor's view of one line.
enum NoteBlockKind: Equatable, Sendable {
  case paragraph
  case heading(Int)
  case bullet
  case numbered
  case check(done: Bool)
  case quote
  case code

  var isList: Bool {
    switch self {
    case .bullet, .numbered, .check: true
    default: false
    }
  }

  /// Compact tag stored on the attributed text.
  var tag: String {
    switch self {
    case .paragraph: "p"
    case .heading(let level): "h\(level)"
    case .bullet: "ul"
    case .numbered: "ol"
    case .check: "ck"
    case .quote: "q"
    case .code: "code"
    }
  }

  init(tag: String?) {
    switch tag {
    case "h1": self = .heading(1)
    case "h2": self = .heading(2)
    case "h3": self = .heading(3)
    case "ul": self = .bullet
    case "ol": self = .numbered
    case "ck": self = .check(done: false)
    case "q": self = .quote
    case "code": self = .code
    default: self = .paragraph
    }
  }

  /// Same kind of line, ignoring a checklist item's ticked state.
  func sameKind(as other: NoteBlockKind) -> Bool { tag == other.tag }
}

/// Inline formatting that can sit on any run of text.
struct NoteInlineStyle: OptionSet, Hashable, Sendable {
  let rawValue: Int
  static let bold = NoteInlineStyle(rawValue: 1)
  static let italic = NoteInlineStyle(rawValue: 2)
  static let underline = NoteInlineStyle(rawValue: 4)
  static let strike = NoteInlineStyle(rawValue: 8)
  static let highlight = NoteInlineStyle(rawValue: 16)
  static let code = NoteInlineStyle(rawValue: 32)
}

struct NoteRun: Equatable, Sendable {
  var text: String
  var style: NoteInlineStyle = []
  var link: String?
}

struct NoteLine: Equatable, Sendable {
  var kind: NoteBlockKind = .paragraph
  /// Nesting depth of a list item (two spaces per level in the file).
  var indent = 0
  var runs: [NoteRun] = []

  var text: String { runs.map(\.text).joined() }
}

/// The marker characters shown in front of list items in the editor. They are real characters in the
/// text view and are dropped again when the note is written back as Markdown.
enum NoteMarker {
  static let bullet = "\u{2022} "
  static let unchecked = "\u{2610} "
  static let checked = "\u{2611} "

  static func string(for kind: NoteBlockKind, number: Int = 1) -> String {
    switch kind {
    case .bullet: bullet
    case .numbered: "\(number). "
    case .check(let done): done ? checked : unchecked
    default: ""
    }
  }

  /// Length of the marker at the start of `line` for a list `kind`, or nil when it is missing or damaged.
  static func length(in line: String, kind: NoteBlockKind) -> Int? {
    switch kind {
    case .bullet: return line.hasPrefix(bullet) ? bullet.utf16.count : nil
    case .check: return (line.hasPrefix(unchecked) || line.hasPrefix(checked)) ? 2 : nil
    case .numbered:
      let digits = line.prefix { $0.isASCII && $0.isNumber }
      guard !digits.isEmpty, digits.count < 6, line.dropFirst(digits.count).hasPrefix(". ") else { return nil }
      return digits.count + 2
    default: return 0
    }
  }
}
