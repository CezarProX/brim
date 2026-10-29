import Foundation

/// Markdown text <-> `NoteLine`s. The file format is plain Markdown, so notes stay readable in any editor.
enum NoteMarkdown {
  private static let blockEscapes: Set<Character> = ["#", "-", "*", "+", ">", "\u{2022}", "\u{2610}", "\u{2611}"]

  static func parse(_ text: String) -> [NoteLine] {
    var lines: [NoteLine] = []
    var inFence = false
    for raw in text.components(separatedBy: "\n") {
      if raw.hasPrefix("```") { inFence.toggle(); continue }
      if inFence {
        lines.append(NoteLine(kind: .code, runs: raw.isEmpty ? [] : [NoteRun(text: raw)]))
      } else {
        lines.append(parseLine(raw))
      }
    }
    return lines
  }

  static func parseLine(_ raw: String) -> NoteLine {
    let spaces = raw.prefix { $0 == " " || $0 == "\t" }
    let indent = min(4, spaces.reduce(0) { $0 + ($1 == "\t" ? 2 : 1) } / 2)
    let body = String(raw.dropFirst(spaces.count))

    if let hashes = Optional(body.prefix { $0 == "#" }), (1...3).contains(hashes.count),
      body.dropFirst(hashes.count).hasPrefix(" ")
    {
      return line(.heading(hashes.count), 0, String(body.dropFirst(hashes.count + 1)))
    }
    for marker in ["- [ ] ", "* [ ] ", "+ [ ] ", "\u{2610} "] where body.hasPrefix(marker) {
      return line(.check(done: false), indent, String(body.dropFirst(marker.count)))
    }
    for marker in ["- [x] ", "- [X] ", "* [x] ", "* [X] ", "+ [x] ", "\u{2611} "] where body.hasPrefix(marker) {
      return line(.check(done: true), indent, String(body.dropFirst(marker.count)))
    }
    for marker in ["- ", "* ", "+ ", "\u{2022} "] where body.hasPrefix(marker) {
      return line(.bullet, indent, String(body.dropFirst(marker.count)))
    }
    let digits = body.prefix { $0.isASCII && $0.isNumber }
    if !digits.isEmpty, digits.count < 6, body.dropFirst(digits.count).hasPrefix(". ") {
      return line(.numbered, indent, String(body.dropFirst(digits.count + 2)))
    }
    if body.hasPrefix("> ") { return line(.quote, 0, String(body.dropFirst(2))) }
    if body.hasPrefix("\\"), let next = body.dropFirst().first, blockEscapes.contains(next) || next.isASCII && next.isNumber {
      return line(.paragraph, 0, String(raw.dropFirst(spaces.count + 1)), keepSpaces: String(spaces))
    }
    return line(.paragraph, 0, raw)
  }

  private static func line(_ kind: NoteBlockKind, _ indent: Int, _ text: String, keepSpaces: String = "") -> NoteLine {
    NoteLine(kind: kind, indent: indent, runs: NoteInlineMarkdown.parse(keepSpaces + text))
  }

  static func serialize(_ lines: [NoteLine]) -> String {
    var out: [String] = []
    var counters: [Int: Int] = [:]
    var inFence = false
    for line in lines {
      if line.kind == .code {
        if !inFence { out.append("```"); inFence = true }
        out.append(line.text)
        continue
      }
      if inFence { out.append("```"); inFence = false }
      if line.kind == .numbered {
        counters[line.indent, default: 0] += 1
        counters = counters.filter { $0.key <= line.indent }
      } else {
        counters.removeAll()
      }
      out.append(serializeLine(line, number: counters[line.indent] ?? 1))
    }
    if inFence { out.append("```") }
    return out.joined(separator: "\n")
  }

  static func serializeLine(_ line: NoteLine, number: Int = 1) -> String {
    let content = NoteInlineMarkdown.serialize(line.runs)
    let pad = String(repeating: "  ", count: line.indent)
    switch line.kind {
    case .heading(let level): return String(repeating: "#", count: level) + " " + content
    case .bullet: return pad + "- " + content
    case .numbered: return pad + "\(number). " + content
    case .check(let done): return pad + (done ? "- [x] " : "- [ ] ") + content
    case .quote: return "> " + content
    case .code: return line.text
    case .paragraph:
      guard looksLikeBlock(content) else { return content }
      let spaces = content.prefix { $0 == " " }
      return String(spaces) + "\\" + String(content.dropFirst(spaces.count))
    }
  }

  /// A plain paragraph that would be read back as a list, heading or quote gets a backslash.
  private static func looksLikeBlock(_ content: String) -> Bool {
    let trimmed = content.drop { $0 == " " }
    guard let first = trimmed.first else { return false }
    if first == "#" { return trimmed.drop { $0 == "#" }.hasPrefix(" ") }
    if ["-", "*", "+", "\u{2022}", "\u{2610}", "\u{2611}"].contains(first) {
      return trimmed.dropFirst().hasPrefix(" ")
    }
    if first == ">" { return trimmed.dropFirst().hasPrefix(" ") }
    if first.isASCII && first.isNumber {
      return trimmed.drop { $0.isASCII && $0.isNumber }.hasPrefix(". ")
    }
    return false
  }
}
