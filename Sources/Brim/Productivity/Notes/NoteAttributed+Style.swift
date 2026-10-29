import AppKit

extension NoteAttributed {
  // MARK: Fonts

  static func font(for kind: NoteBlockKind, style: NoteInlineStyle, text: NoteTextStyle) -> NSFont {
    var size = text.base
    var weight = NSFont.Weight.regular
    switch kind {
    case .heading(let level):
      size = text.base * (level == 1 ? 1.7 : level == 2 ? 1.4 : 1.2)
      weight = .bold
    case .code: size = text.base * 0.92
    default: break
    }
    if style.contains(.bold) { weight = .bold }
    let monospaced = kind == .code || style.contains(.code)
    var font =
      monospaced
      ? NSFont.monospacedSystemFont(ofSize: monospaced && kind != .code ? text.base * 0.92 : size, weight: weight)
      : NSFont.systemFont(ofSize: size, weight: weight)
    if style.contains(.italic) {
      let descriptor = font.fontDescriptor.withSymbolicTraits(font.fontDescriptor.symbolicTraits.union(.italic))
      font = NSFont(descriptor: descriptor, size: font.pointSize) ?? font
    }
    return font
  }

  // MARK: Styling

  /// Recomputes every visual attribute from the semantic ones. Safe to call after any edit.
  static func restyle(_ storage: NSMutableAttributedString, style: NoteTextStyle) {
    let string = storage.string as NSString
    guard string.length > 0 else { return }
    storage.beginEditing()
    defer { storage.endEditing() }
    var location = 0
    while location < string.length {
      let paragraph = string.paragraphRange(for: NSRange(location: location, length: 0))
      location = NSMaxRange(paragraph)
      var content = paragraph
      if content.length > 0, string.character(at: NSMaxRange(content) - 1) == 0x0A { content.length -= 1 }
      stylize(paragraph: paragraph, content: content, in: storage, text: style)
    }
  }

  private static func stylize(
    paragraph: NSRange, content: NSRange, in storage: NSMutableAttributedString, text: NoteTextStyle
  ) {
    let string = storage.string as NSString
    let probe = paragraph.length > 0
    var kind = NoteBlockKind(tag: probe ? storage.attribute(NoteAttr.block, at: paragraph.location, effectiveRange: nil) as? String : nil)
    let indent = probe ? storage.attribute(NoteAttr.indent, at: paragraph.location, effectiveRange: nil) as? Int ?? 0 : 0
    var markerLength = 0
    if kind.isList {
      let line = string.substring(with: content)
      if let length = NoteMarker.length(in: line, kind: kind) {
        markerLength = length
        if case .check = kind { kind = .check(done: line.hasPrefix(NoteMarker.checked)) }
      } else { kind = .paragraph }
    }
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.paragraphSpacing = text.base * 0.25
    let step = text.base * 1.4
    let hang: CGFloat
    switch kind {
    case .bullet, .check: hang = text.base * 1.45
    case .numbered: hang = text.base * 1.9
    case .quote: hang = text.base * 0.9
    default: hang = 0
    }
    paragraphStyle.firstLineHeadIndent = CGFloat(indent) * step
    paragraphStyle.headIndent = CGFloat(indent) * step + hang
    if case .heading = kind { paragraphStyle.paragraphSpacingBefore = text.base * 0.5 }

    let done: Bool
    if case .check(let value) = kind { done = value } else { done = false }
    let visual: [NSAttributedString.Key] = [.underlineStyle, .strikethroughStyle, .backgroundColor]
    visual.forEach { storage.removeAttribute($0, range: paragraph) }
    storage.addAttributes(
      [
        .font: font(for: kind, style: [], text: text), .foregroundColor: kind == .quote || done ? text.secondary : text.text,
        .paragraphStyle: paragraphStyle, NoteAttr.block: kind.tag, NoteAttr.indent: indent,
      ], range: paragraph)
    if kind == .code { storage.addAttribute(.backgroundColor, value: NSColor(white: 1, alpha: 0.07), range: content) }
    if markerLength > 0 {
      let marker = NSRange(location: content.location, length: markerLength)
      let tint = done ? text.accent : text.secondary
      storage.addAttributes([.foregroundColor: tint, .strikethroughStyle: 0], range: marker)
    }
    let body = NSRange(location: content.location + markerLength, length: content.length - markerLength)
    guard body.length > 0 else { return }
    var runs: [(NSRange, [NSAttributedString.Key: Any])] = []
    storage.enumerateAttributes(in: body, options: []) { attributes, range, _ in runs.append((range, attributes)) }
    for (range, attributes) in runs {
      let inline = NoteInlineStyle(rawValue: attributes[NoteAttr.style] as? Int ?? 0)
      var extra: [NSAttributedString.Key: Any] = [.font: font(for: kind, style: inline, text: text)]
      if inline.contains(.underline) { extra[.underlineStyle] = NSUnderlineStyle.single.rawValue }
      if inline.contains(.strike) || done { extra[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
      if inline.contains(.highlight) { extra[.backgroundColor] = text.accent.withAlphaComponent(0.38) }
      if inline.contains(.code) { extra[.backgroundColor] = NSColor(white: 1, alpha: 0.12) }
      if attributes[.link] != nil {
        extra[.foregroundColor] = text.link
        extra[.underlineStyle] = NSUnderlineStyle.single.rawValue
      }
      storage.addAttributes(extra, range: range)
    }
  }

  // MARK: Normalising

  /// Repairs list markers after an edit (damaged marker -> plain paragraph) and renumbers ordered lists.
  /// Returns the character offsets that changed as (location, delta) so the caller can move the caret.
  @discardableResult
  static func normalize(_ storage: NSMutableAttributedString) -> [(location: Int, delta: Int)] {
    var edits: [(location: Int, delta: Int)] = []
    let string = storage.string as NSString
    guard string.length > 0 else { return edits }
    var counters: [Int: Int] = [:]
    var fixes: [(range: NSRange, text: String)] = []
    var location = 0
    while location < string.length {
      let paragraph = string.paragraphRange(for: NSRange(location: location, length: 0))
      location = NSMaxRange(paragraph)
      var content = paragraph
      if content.length > 0, string.character(at: NSMaxRange(content) - 1) == 0x0A { content.length -= 1 }
      guard content.length > 0 else { counters.removeAll(); continue }
      var kind = NoteBlockKind(tag: storage.attribute(NoteAttr.block, at: content.location, effectiveRange: nil) as? String)
      let indent = storage.attribute(NoteAttr.indent, at: content.location, effectiveRange: nil) as? Int ?? 0
      let line = string.substring(with: content)
      if kind.isList, NoteMarker.length(in: line, kind: kind) == nil {
        storage.addAttribute(NoteAttr.block, value: NoteBlockKind.paragraph.tag, range: paragraph)
        kind = .paragraph
      }
      if kind == .numbered {
        counters[indent, default: 0] += 1
        counters = counters.filter { $0.key <= indent }
        let wanted = NoteMarker.string(for: .numbered, number: counters[indent] ?? 1)
        if let length = NoteMarker.length(in: line, kind: .numbered), string.substring(with: NSRange(location: content.location, length: length)) != wanted {
          fixes.append((NSRange(location: content.location, length: length), wanted))
        }
      } else { counters.removeAll() }
    }
    for fix in fixes.reversed() {
      let attributes = storage.attributes(at: fix.range.location, effectiveRange: nil)
      storage.replaceCharacters(in: fix.range, with: NSAttributedString(string: fix.text, attributes: attributes))
      edits.append((fix.range.location, fix.text.utf16.count - fix.range.length))
    }
    return edits
  }
}
