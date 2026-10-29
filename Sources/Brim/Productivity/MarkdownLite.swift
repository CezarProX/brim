import Foundation

/// One rendered line of a note: headings, bullets, checkboxes, quotes, code, and plain text.
enum MarkdownBlock: Equatable {
  case heading(level: Int, text: String)
  case bullet(text: String)
  case checkbox(done: Bool, text: String)
  case quote(text: String)
  case code(text: String)
  case paragraph(text: String)
  case blank
}

enum MarkdownLite {
  static func blocks(_ text: String) -> [MarkdownBlock] {
    var inFence = false
    return text.components(separatedBy: "\n").prefix(2000).map { line in
      if line.hasPrefix("```") { inFence.toggle(); return .blank }
      if inFence { return .code(text: line) }
      return block(for: line)
    }
  }

  static func block(for line: String) -> MarkdownBlock {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    if trimmed.isEmpty { return .blank }
    if let hashes = trimmed.prefix(while: { $0 == "#" }) as Substring?, (1...3).contains(hashes.count),
      trimmed.dropFirst(hashes.count).hasPrefix(" ")
    {
      return .heading(level: hashes.count, text: String(trimmed.dropFirst(hashes.count + 1)))
    }
    for marker in ["- [ ] ", "* [ ] "] where trimmed.hasPrefix(marker) {
      return .checkbox(done: false, text: String(trimmed.dropFirst(marker.count)))
    }
    for marker in ["- [x] ", "- [X] ", "* [x] "] where trimmed.hasPrefix(marker) {
      return .checkbox(done: true, text: String(trimmed.dropFirst(marker.count)))
    }
    for marker in ["- ", "* ", "+ "] where trimmed.hasPrefix(marker) {
      return .bullet(text: String(trimmed.dropFirst(marker.count)))
    }
    if trimmed.hasPrefix("> ") { return .quote(text: String(trimmed.dropFirst(2))) }
    return .paragraph(text: trimmed)
  }

  /// Inline **bold**, *italic*, `code` and links as an AttributedString; plain text if parsing fails.
  static func inline(_ text: String) -> AttributedString {
    let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
    return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
  }

  /// Flips the checkbox on a given line of the note text.
  static func toggleCheckbox(in text: String, line index: Int) -> String {
    var lines = text.components(separatedBy: "\n")
    guard lines.indices.contains(index) else { return text }
    let line = lines[index]
    if let range = line.range(of: "- [ ] ") ?? line.range(of: "* [ ] ") {
      lines[index] = line.replacingCharacters(in: range, with: "- [x] ")
    } else if let range = line.range(of: "- [x] ") ?? line.range(of: "- [X] ") ?? line.range(of: "* [x] ") {
      lines[index] = line.replacingCharacters(in: range, with: "- [ ] ")
    }
    return lines.joined(separator: "\n")
  }
}
