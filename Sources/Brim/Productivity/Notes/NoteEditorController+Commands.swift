import AppKit

extension NoteEditorController {
  // MARK: Inline formatting

  func toggle(_ flag: NoteInlineStyle) {
    guard let view = textView, let storage = view.textStorage else { return }
    let selection = view.selectedRange()
    if selection.length == 0 {
      var typing = view.typingAttributes
      var raw = NoteInlineStyle(rawValue: typing[NoteAttr.style] as? Int ?? 0)
      if raw.contains(flag) { raw.remove(flag) } else { raw.insert(flag) }
      typing[NoteAttr.style] = raw.rawValue
      view.typingAttributes = typing
      updateFormat()
      return
    }
    let ranges = contentRanges(in: selection)
    guard !ranges.isEmpty else { return }
    var everyRunHasIt = true
    for range in ranges {
      storage.enumerateAttribute(NoteAttr.style, in: range, options: []) { value, _, _ in
        if !NoteInlineStyle(rawValue: value as? Int ?? 0).contains(flag) { everyRunHasIt = false }
      }
    }
    guard view.shouldChangeText(in: selection, replacementString: nil) else { return }
    for range in ranges {
      var updates: [(NSRange, Int)] = []
      storage.enumerateAttribute(NoteAttr.style, in: range, options: []) { value, run, _ in
        var raw = NoteInlineStyle(rawValue: value as? Int ?? 0)
        if everyRunHasIt { raw.remove(flag) } else { raw.insert(flag) }
        updates.append((run, raw.rawValue))
      }
      for (run, raw) in updates { storage.addAttribute(NoteAttr.style, value: raw, range: run) }
    }
    view.didChangeText()
  }

  /// The parts of `selection` that are text (not list markers or line breaks).
  private func contentRanges(in selection: NSRange) -> [NSRange] {
    guard let storage = textView?.textStorage else { return [] }
    let string = storage.string as NSString
    var ranges: [NSRange] = []
    var location = string.lineRange(for: NSRange(location: selection.location, length: 0)).location
    while location < NSMaxRange(selection) || location == selection.location {
      guard let info = lineInfo(at: location) else { break }
      let start = info.content.location + info.markerLength
      let clipped = NSIntersectionRange(
        NSRange(location: start, length: info.content.length - info.markerLength), selection)
      if clipped.length > 0 { ranges.append(clipped) }
      let next = NSMaxRange(info.content) + 1
      if next <= location || next > string.length { break }
      location = next
    }
    return ranges
  }

  // MARK: Block formatting

  /// Sets the kind of every selected line, or turns it back into a paragraph when they all have it already.
  func setBlock(_ kind: NoteBlockKind) {
    guard let view = textView, let storage = view.textStorage else { return }
    let string = storage.string as NSString
    let span = string.lineRange(for: view.selectedRange())
    var content = span
    if content.length > 0, string.character(at: NSMaxRange(content) - 1) == 0x0A { content.length -= 1 }
    let lines = NoteAttributed.lines(from: storage, in: content)
    let removing = lines.allSatisfy { $0.kind.sameKind(as: kind) }
    let changed = lines.map { line -> NoteLine in
      var next = line
      next.kind = removing ? .paragraph : kind
      if !next.kind.isList { next.indent = 0 }
      return next
    }
    let replacement = NoteAttributed.attributed(lines: changed, style: style)
    guard view.shouldChangeText(in: content, replacementString: replacement.string) else { return }
    storage.replaceCharacters(in: content, with: replacement)
    view.didChangeText()
    if replacement.length == 0 {
      view.typingAttributes = baseTypingAttributes(block: removing ? .paragraph : kind)
    }
    let caret = content.location + replacement.length
    view.setSelectedRange(
      content.length > 0 && view.selectedRange().length > 0
        ? NSRange(location: content.location, length: replacement.length) : NSRange(location: caret, length: 0))
    updateFormat()
  }

  // MARK: Links

  func toggleLink() {
    guard let view = textView, let storage = view.textStorage else { return }
    let selection = view.selectedRange()
    guard selection.length > 0 else { return }
    if format.hasLink {
      guard view.shouldChangeText(in: selection, replacementString: nil) else { return }
      storage.removeAttribute(.link, range: selection)
      view.didChangeText()
      return
    }
    guard let target = requestLink(nil) else { return }
    guard view.shouldChangeText(in: selection, replacementString: nil) else { return }
    storage.addAttribute(.link, value: URL(string: target) ?? target, range: selection)
    view.didChangeText()
  }

  // MARK: Checklists

  func toggleChecklist(at index: Int) {
    guard let view = textView, let storage = view.textStorage, index < storage.length else { return }
    let range = NSRange(location: index, length: 1)
    let current = (storage.string as NSString).substring(with: range)
    let next = current == "\u{2611}" ? "\u{2610}" : "\u{2611}"
    guard view.shouldChangeText(in: range, replacementString: next) else { return }
    storage.replaceCharacters(in: range, with: NSAttributedString(string: next, attributes: storage.attributes(at: index, effectiveRange: nil)))
    view.didChangeText()
  }

  // MARK: Pasting

  func insert(markdown: String) {
    guard let view = textView, let storage = view.textStorage else { return }
    let selection = view.selectedRange()
    let lines = NoteMarkdown.parse(markdown)
    guard !lines.isEmpty else { return }
    let here = lineInfo(at: selection.location)
    let onBlankLine = here.map { $0.content.length == $0.markerLength } ?? true
    let result = NSMutableAttributedString()
    if onBlankLine && selection.length == 0 && !(here?.kind.isList ?? false) {
      result.append(NoteAttributed.attributed(lines: lines, style: style))
    } else {
      // The first pasted line continues the current one; later lines keep their own kind.
      let block = here?.kind ?? .paragraph
      let first = NoteAttributed.inline(runs: lines[0].runs)
      first.addAttributes([NoteAttr.block: block.tag, NoteAttr.indent: here?.indent ?? 0], range: NSRange(location: 0, length: first.length))
      result.append(first)
      if lines.count > 1 {
        result.append(NSAttributedString(string: "\n", attributes: [NoteAttr.block: block.tag, NoteAttr.indent: here?.indent ?? 0]))
        result.append(NoteAttributed.attributed(lines: Array(lines.dropFirst()), style: style))
      }
    }
    guard view.shouldChangeText(in: selection, replacementString: result.string) else { return }
    storage.replaceCharacters(in: selection, with: result)
    view.didChangeText()
    view.setSelectedRange(NSRange(location: selection.location + result.length, length: 0))
  }

  // MARK: Keys

  func handleNewline() -> Bool {
    guard let view = textView, let storage = view.textStorage else { return false }
    let selection = view.selectedRange()
    guard let info = lineInfo(at: selection.location) else { return false }
    if info.kind.isList {
      if info.content.length == info.markerLength, selection.length == 0 {
        return leaveBlock(info)
      }
      let next: NoteBlockKind
      if case .check = info.kind { next = .check(done: false) } else { next = info.kind }
      let marker = NoteMarker.string(for: next, number: 99)
      let insertion = NSMutableAttributedString(string: "\n" + marker)
      insertion.addAttributes(
        [NoteAttr.block: info.kind.tag, NoteAttr.indent: info.indent, NoteAttr.style: 0], range: NSRange(location: 0, length: insertion.length))
      let caret = max(selection.location, info.content.location + info.markerLength)
      let range = NSRange(location: caret, length: selection.length - (caret - selection.location))
      guard view.shouldChangeText(in: range, replacementString: insertion.string) else { return true }
      storage.replaceCharacters(in: range, with: insertion)
      view.didChangeText()
      view.setSelectedRange(NSRange(location: caret + insertion.length, length: 0))
      return true
    }
    if case .heading = info.kind {
      let newline = NSAttributedString(string: "\n", attributes: baseTypingAttributes(block: info.kind).merging([NoteAttr.block: info.kind.tag]) { $1 })
      guard view.shouldChangeText(in: selection, replacementString: "\n") else { return true }
      storage.replaceCharacters(in: selection, with: newline)
      view.didChangeText()
      let caret = selection.location + 1
      if let after = lineInfo(at: caret), after.content.length > 0 {
        storage.addAttribute(NoteAttr.block, value: NoteBlockKind.paragraph.tag, range: after.content)
        finishEdit()
      }
      view.setSelectedRange(NSRange(location: caret, length: 0))
      view.typingAttributes = baseTypingAttributes()
      return true
    }
    return false
  }

  func handleBackspace() -> Bool {
    guard let view = textView, view.selectedRange().length == 0,
      let info = lineInfo(at: view.selectedRange().location)
    else { return false }
    let caret = view.selectedRange().location
    if info.kind.isList, caret >= info.content.location, caret <= info.content.location + info.markerLength {
      if info.indent > 0 { return shiftIndent(by: -1) }
      return leaveBlock(info)
    }
    switch info.kind {
    case .heading, .quote:
      if caret == info.content.location, info.content.length > 0 { return leaveBlock(info) }
    default: break
    }
    return false
  }

  /// Turns a list item, heading or quote back into a plain paragraph, dropping any marker.
  private func leaveBlock(_ info: LineInfo) -> Bool {
    guard let view = textView, let storage = view.textStorage else { return false }
    let marker = NSRange(location: info.content.location, length: info.markerLength)
    guard view.shouldChangeText(in: marker, replacementString: "") else { return true }
    if marker.length > 0 { storage.deleteCharacters(in: marker) }
    let line = NSRange(location: info.content.location, length: info.content.length - info.markerLength)
    if line.length > 0 {
      storage.addAttributes([NoteAttr.block: NoteBlockKind.paragraph.tag, NoteAttr.indent: 0], range: line)
    }
    view.didChangeText()
    view.typingAttributes = baseTypingAttributes()
    return true
  }

  func shiftIndent(by delta: Int) -> Bool {
    guard let view = textView, let storage = view.textStorage,
      let info = lineInfo(at: view.selectedRange().location), info.kind.isList
    else { return false }
    let next = max(0, min(4, info.indent + delta))
    guard next != info.indent else { return true }
    guard view.shouldChangeText(in: info.content, replacementString: nil) else { return true }
    storage.addAttribute(NoteAttr.indent, value: next, range: NSRange(location: info.content.location, length: info.content.length))
    view.didChangeText()
    return true
  }
}
