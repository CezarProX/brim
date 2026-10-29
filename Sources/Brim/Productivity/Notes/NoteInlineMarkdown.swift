import Foundation

/// Inline Markdown <-> styled runs. Supports **bold**, *italic* / _italic_, <u>underline</u>,
/// ~~strike~~, ==highlight==, `code` and [links](url); anything else stays literal text.
enum NoteInlineMarkdown {
  private enum Mark: Equatable { case bold, italic, strike, highlight, underline, link }

  private enum Token {
    case text(String)
    case code(String)
    case open(Mark, literal: String, url: String?)
    case close(Mark)
  }

  private static let escapable: Set<Character> = ["\\", "*", "_", "`", "~", "=", "[", "]", "<"]

  // MARK: Parsing

  static func parse(_ source: String) -> [NoteRun] {
    resolve(tokenize(Array(source)))
  }

  private static func tokenize(_ chars: [Character]) -> [Token] {
    var tokens: [Token] = []
    var stack: [(mark: Mark, index: Int, char: Character)] = []
    var buffer = ""
    var i = 0
    let n = chars.count

    func flush() {
      if !buffer.isEmpty { tokens.append(.text(buffer)); buffer = "" }
    }
    func open(_ mark: Mark, _ literal: String, _ char: Character) {
      flush()
      stack.append((mark, tokens.count, char))
      tokens.append(.open(mark, literal: literal, url: nil))
    }
    func close(_ mark: Mark) {
      flush()
      stack.removeLast()
      tokens.append(.close(mark))
    }
    func startsWith(_ s: String, at index: Int) -> Bool {
      let pattern = Array(s)
      return index + pattern.count <= n && Array(chars[index..<index + pattern.count]) == pattern
    }
    func isSpace(_ index: Int) -> Bool { index < 0 || index >= n || chars[index].isWhitespace }
    func isWordChar(_ index: Int) -> Bool { index >= 0 && index < n && (chars[index].isLetter || chars[index].isNumber) }

    while i < n {
      let c = chars[i]
      if c == "\\", i + 1 < n, escapable.contains(chars[i + 1]) {
        buffer.append(chars[i + 1]); i += 2; continue
      }
      if c == "`" {
        var k = 0
        while i + k < n, chars[i + k] == "`" { k += 1 }
        if let end = closingBackticks(chars, from: i + k, count: k) {
          flush()
          var body = String(chars[(i + k)..<end])
          if body.count > 2, body.hasPrefix(" "), body.hasSuffix(" "), !body.allSatisfy({ $0 == " " }) {
            body = String(body.dropFirst().dropLast())
          }
          tokens.append(.code(body))
          i = end + k
        } else {
          buffer += String(repeating: "`", count: k); i += k
        }
        continue
      }
      if c == "*" || c == "_" {
        var k = 0
        while i + k < n, chars[i + k] == c { k += 1 }
        let underscore = c == "_"
        let canClose = !isSpace(i - 1) && !(underscore && isWordChar(i + k))
        let canOpen = !isSpace(i + k) && !(underscore && isWordChar(i - 1))
        var remaining = k
        while remaining > 0, canClose, let top = stack.last, top.char == c {
          if top.mark == .italic { close(.italic); remaining -= 1 } else if top.mark == .bold, remaining >= 2 {
            close(.bold); remaining -= 2
          } else { break }
        }
        if remaining > 0 {
          if canOpen {
            while remaining >= 2 { open(.bold, String(repeating: c, count: 2), c); remaining -= 2 }
            if remaining == 1 { open(.italic, String(c), c) }
          } else {
            buffer += String(repeating: c, count: remaining)
          }
        }
        i += k; continue
      }
      if (c == "~" || c == "=") && i + 1 < n && chars[i + 1] == c {
        let mark: Mark = c == "~" ? .strike : .highlight
        let literal = String(repeating: c, count: 2)
        if stack.last?.mark == mark, !isSpace(i - 1) {
          close(mark)
        } else if !isSpace(i + 2), !stack.contains(where: { $0.mark == mark }) {
          open(mark, literal, c)
        } else {
          buffer += literal
        }
        i += 2; continue
      }
      if startsWith("<u>", at: i) {
        if stack.contains(where: { $0.mark == .underline }) { buffer += "<u>" } else { open(.underline, "<u>", "<") }
        i += 3; continue
      }
      if startsWith("</u>", at: i) {
        if stack.last?.mark == .underline { close(.underline) } else { buffer += "</u>" }
        i += 4; continue
      }
      if c == "[" {
        open(.link, "[", "["); i += 1; continue
      }
      if c == "]", i + 1 < n, chars[i + 1] == "(", stack.last?.mark == .link,
        let end = chars[(i + 2)...].firstIndex(of: ")"), !chars[(i + 2)..<end].contains("\n")
      {
        let url = String(chars[(i + 2)..<end])
        if case .open(.link, let literal, _) = tokens[stack[stack.count - 1].index] {
          tokens[stack[stack.count - 1].index] = .open(.link, literal: literal, url: url)
        }
        close(.link)
        i = end + 1; continue
      }
      buffer.append(c); i += 1
    }
    flush()
    // Openers that never found their closer are just characters.
    for entry in stack {
      if case .open(_, let literal, _) = tokens[entry.index] { tokens[entry.index] = .text(literal) }
    }
    return tokens
  }

  private static func closingBackticks(_ chars: [Character], from start: Int, count: Int) -> Int? {
    var i = start
    while i < chars.count {
      if chars[i] == "`" {
        var k = 0
        while i + k < chars.count, chars[i + k] == "`" { k += 1 }
        if k == count { return i }
        i += k
      } else { i += 1 }
    }
    return nil
  }

  private static func resolve(_ tokens: [Token]) -> [NoteRun] {
    var runs: [NoteRun] = []
    var style: NoteInlineStyle = []
    var links: [String] = []
    func add(_ text: String, _ extra: NoteInlineStyle = []) {
      guard !text.isEmpty else { return }
      let run = NoteRun(text: text, style: style.union(extra), link: links.last)
      if let last = runs.last, last.style == run.style, last.link == run.link {
        runs[runs.count - 1].text += text
      } else { runs.append(run) }
    }
    for token in tokens {
      switch token {
      case .text(let text): add(text)
      case .code(let text): add(text, .code)
      case .open(let mark, _, let url):
        if mark == .link { links.append(url ?? "") } else { style.insert(flag(mark)) }
      case .close(let mark):
        if mark == .link { links.removeLast() } else { style.remove(flag(mark)) }
      }
    }
    return runs
  }

  private static func flag(_ mark: Mark) -> NoteInlineStyle {
    switch mark {
    case .bold: .bold
    case .italic: .italic
    case .strike: .strike
    case .highlight: .highlight
    case .underline: .underline
    case .link: []
    }
  }

  // MARK: Serializing

  private enum Layer: Equatable {
    case link(String), bold, italic, strike, highlight, underline

    var open: String {
      switch self {
      case .link: "["
      case .bold: "**"
      case .italic: "*"
      case .strike: "~~"
      case .highlight: "=="
      case .underline: "<u>"
      }
    }
    var close: String {
      switch self {
      case .link(let url): "](\(url))"
      case .underline: "</u>"
      default: open
      }
    }
  }

  static func serialize(_ runs: [NoteRun]) -> String {
    let runs = runs.filter { !$0.text.isEmpty }
    let flat = Array(runs.map(\.text).joined())
    var out = ""
    var openLayers: [Layer] = []
    var pendingTrailing = ""
    var offset = 0
    for (index, run) in runs.enumerated() {
      let wanted = layers(for: run)
      let common = commonPrefix(openLayers, wanted)
      for layer in openLayers[common...].reversed() { out += layer.close }
      openLayers = Array(openLayers[..<common])
      out += pendingTrailing
      pendingTrailing = ""
      var text = Array(run.text)
      var lead: [Character] = []
      var trail: [Character] = []
      if !run.style.contains(.code) {
        // A delimiter hugging a space is not read back, so edge spaces sit outside the markers that open or close here.
        if wanted.count > common { lead = Array(text.prefix { $0 == " " || $0 == "\t" }); text.removeFirst(lead.count) }
        let nextWanted = index + 1 < runs.count ? layers(for: runs[index + 1]) : []
        if commonPrefix(wanted, nextWanted) < wanted.count {
          trail = Array(text.reversed().prefix { $0 == " " || $0 == "\t" }.reversed())
          text.removeLast(trail.count)
        }
      }
      out += escape(lead, around: flat, offset: offset)
      if text.isEmpty { openLayers = Array(openLayers[..<min(common, openLayers.count)]) } else {
        for layer in wanted[common...] { out += layer.open; openLayers.append(layer) }
      }
      if run.style.contains(.code) {
        out += codeSpan(run.text)
      } else {
        out += escape(text, around: flat, offset: offset + lead.count)
      }
      pendingTrailing = escape(trail, around: flat, offset: offset + lead.count + text.count)
      offset += run.text.count
    }
    for layer in openLayers.reversed() { out += layer.close }
    return out + pendingTrailing
  }

  private static func commonPrefix(_ a: [Layer], _ b: [Layer]) -> Int {
    var common = 0
    while common < min(a.count, b.count), a[common] == b[common] { common += 1 }
    return common
  }

  private static func layers(for run: NoteRun) -> [Layer] {
    var result: [Layer] = []
    if let link = run.link { result.append(.link(link)) }
    if run.style.contains(.code) { return result }
    if run.style.contains(.bold) { result.append(.bold) }
    if run.style.contains(.italic) { result.append(.italic) }
    if run.style.contains(.strike) { result.append(.strike) }
    if run.style.contains(.highlight) { result.append(.highlight) }
    if run.style.contains(.underline) { result.append(.underline) }
    return result
  }

  private static func codeSpan(_ text: String) -> String {
    var longest = 0, current = 0
    for ch in text {
      current = ch == "`" ? current + 1 : 0
      longest = max(longest, current)
    }
    let fence = String(repeating: "`", count: longest + 1)
    let pad = text.hasPrefix("`") || text.hasSuffix("`") || (text.hasPrefix(" ") && text.hasSuffix(" ")) ? " " : ""
    return fence + pad + text + pad + fence
  }

  private static func escape(_ text: [Character], around flat: [Character], offset: Int) -> String {
    var out = ""
    func spaceOrEdge(_ ch: Character?) -> Bool { ch == nil || ch!.isWhitespace }
    func word(_ ch: Character?) -> Bool { ch.map { $0.isLetter || $0.isNumber } ?? false }
    func char(_ index: Int) -> Character? { index >= 0 && index < flat.count ? flat[index] : nil }
    for (j, c) in text.enumerated() {
      let at = offset + j
      let prev = char(at - 1), next = char(at + 1)
      var needs = false
      switch c {
      case "`": needs = true
      case "*", "_", "~", "=":
        var start = at, end = at
        while char(start - 1) == c { start -= 1 }
        while char(end + 1) == c { end += 1 }
        let before = char(start - 1), after = char(end + 1)
        let inert = spaceOrEdge(before) && spaceOrEdge(after)
        let intraWord = c == "_" && word(before) && word(after)
        needs = !inert && !intraWord && (c == "*" || c == "_" || end > start)
      case "]": needs = next == "("
      case "<": needs = (next == "u" && char(at + 2) == ">") || (next == "/" && char(at + 2) == "u" && char(at + 3) == ">")
      case "\\": needs = next.map { escapable.contains($0) } ?? false
      default: break
      }
      if needs { out.append("\\") }
      out.append(c)
    }
    return out
  }
}
