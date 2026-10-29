import AppKit

/// Semantic attributes carried by the editor's text. Everything the Markdown needs is read from these;
/// fonts and colours are derived from them (`NoteAttributed.restyle`), never the other way round.
enum NoteAttr {
  static let block = NSAttributedString.Key("brim.note.block")
  static let indent = NSAttributedString.Key("brim.note.indent")
  static let style = NSAttributedString.Key("brim.note.style")
}

struct NoteTextStyle: Equatable {
  var base: CGFloat = 13
  var text = NSColor.white
  var secondary = NSColor(white: 1, alpha: 0.55)
  var accent = NSColor(red: 1, green: 0.8, blue: 0.2, alpha: 1)
  var link = NSColor(red: 0.45, green: 0.7, blue: 1, alpha: 1)

  static let island = NoteTextStyle(base: 12.5)
  static func window(size: CGFloat) -> NoteTextStyle { NoteTextStyle(base: size) }
}

enum NoteAttributed {
  // MARK: Markdown -> attributed text

  static func attributed(markdown: String, style: NoteTextStyle) -> NSMutableAttributedString {
    attributed(lines: NoteMarkdown.parse(markdown), style: style)
  }

  static func attributed(lines: [NoteLine], style: NoteTextStyle) -> NSMutableAttributedString {
    let result = NSMutableAttributedString()
    var counters: [Int: Int] = [:]
    for (index, line) in lines.enumerated() {
      if line.kind == .numbered {
        counters[line.indent, default: 0] += 1
        counters = counters.filter { $0.key <= line.indent }
      } else { counters.removeAll() }
      let piece = NSMutableAttributedString(string: NoteMarker.string(for: line.kind, number: counters[line.indent] ?? 1))
      piece.append(inline(runs: line.runs))
      if index < lines.count - 1 { piece.append(NSAttributedString(string: "\n")) }
      piece.addAttributes(
        [NoteAttr.block: line.kind.tag, NoteAttr.indent: line.indent], range: NSRange(location: 0, length: piece.length))
      result.append(piece)
    }
    restyle(result, style: style)
    return result
  }

  /// The styled runs as attributed text, carrying only the semantic attributes.
  static func inline(runs: [NoteRun]) -> NSMutableAttributedString {
    let result = NSMutableAttributedString()
    for run in runs {
      var attributes: [NSAttributedString.Key: Any] = [NoteAttr.style: run.style.rawValue]
      if let link = run.link { attributes[.link] = URL(string: link) ?? link }
      result.append(NSAttributedString(string: run.text, attributes: attributes))
    }
    return result
  }

  // MARK: Attributed text -> Markdown

  static func markdown(from text: NSAttributedString) -> String {
    NoteMarkdown.serialize(lines(from: text, in: NSRange(location: 0, length: text.length)))
  }

  /// The lines inside `range`, which must start and end on line boundaries (no trailing newline).
  static func lines(from text: NSAttributedString, in range: NSRange) -> [NoteLine] {
    let string = text.string as NSString
    var lines: [NoteLine] = []
    var location = range.location
    let end = NSMaxRange(range)
    while true {
      let newline = string.range(of: "\n", options: [], range: NSRange(location: location, length: end - location))
      let contentEnd = newline.location == NSNotFound ? end : newline.location
      lines.append(line(from: text, content: NSRange(location: location, length: contentEnd - location)))
      if newline.location == NSNotFound { break }
      location = NSMaxRange(newline)
    }
    return lines
  }

  private static func line(from text: NSAttributedString, content: NSRange) -> NoteLine {
    let string = text.string as NSString
    var kind = NoteBlockKind.paragraph
    var indent = 0
    // An empty line is only marked on its line break.
    if content.location < string.length {
      kind = NoteBlockKind(tag: text.attribute(NoteAttr.block, at: content.location, effectiveRange: nil) as? String)
      indent = text.attribute(NoteAttr.indent, at: content.location, effectiveRange: nil) as? Int ?? 0
    }
    var body = content
    if kind.isList {
      let lineString = string.substring(with: content)
      if let length = NoteMarker.length(in: lineString, kind: kind) {
        if case .check = kind { kind = .check(done: lineString.hasPrefix(NoteMarker.checked)) }
        body = NSRange(location: content.location + length, length: content.length - length)
      } else { kind = .paragraph; indent = 0 }
    }
    var runs: [NoteRun] = []
    if body.length > 0 {
      text.enumerateAttributes(in: body, options: []) { attributes, range, _ in
        let piece = string.substring(with: range)
        let style = NoteInlineStyle(rawValue: attributes[NoteAttr.style] as? Int ?? 0)
        let link = (attributes[.link] as? URL)?.absoluteString ?? attributes[.link] as? String
        if let last = runs.last, last.style == style, last.link == link {
          runs[runs.count - 1].text += piece
        } else {
          runs.append(NoteRun(text: piece, style: style, link: link))
        }
      }
    }
    if kind == .code { runs = runs.isEmpty ? [] : [NoteRun(text: runs.map(\.text).joined())] }
    return NoteLine(kind: kind, indent: indent, runs: runs)
  }
}
