import AppKit
import SwiftUI

/// Drives one rich text view: loads and saves Markdown, keeps the formatting bar in sync with the
/// caret and handles list behaviour (Enter continues a list, Backspace leaves it, Tab nests).
@MainActor
final class NoteEditorController: NSObject, ObservableObject, NSTextViewDelegate {
  struct Format: Equatable {
    var inline: NoteInlineStyle = []
    var block: NoteBlockKind = .paragraph
    var hasLink = false
  }

  @Published private(set) var format = Format()
  var onMarkdownChange: ((String) -> Void)?
  /// Asks for a link target; nil cancels. Replaceable so tests and other hosts can answer without a dialog.
  var requestLink: (String?) -> String? = NoteEditorController.promptForLink

  private(set) weak var textView: NoteTextView?
  private(set) var style = NoteTextStyle.island
  private var lastMarkdown = ""
  private var isLoading = false

  var markdown: String { textView?.textStorage.map(NoteAttributed.markdown(from:)) ?? lastMarkdown }

  // MARK: Wiring

  func attach(_ view: NoteTextView, style: NoteTextStyle) {
    textView = view
    self.style = style
    view.delegate = self
    view.toggleChecklist = { [weak self] index in self?.toggleChecklist(at: index) }
  }

  func load(markdown: String) {
    guard let view = textView, let storage = view.textStorage else { return }
    isLoading = true
    defer { isLoading = false }
    let selection = view.selectedRange()
    storage.setAttributedString(NoteAttributed.attributed(markdown: markdown, style: style))
    lastMarkdown = markdown
    view.setSelectedRange(NSRange(location: min(selection.location, storage.length), length: 0))
    view.typingAttributes = baseTypingAttributes()
    updateFormat()
  }

  func loadIfChanged(markdown: String) {
    if markdown != lastMarkdown { load(markdown: markdown) }
  }

  func setStyle(_ new: NoteTextStyle) {
    guard new != style, let storage = textView?.textStorage else { return }
    style = new
    NoteAttributed.restyle(storage, style: new)
    textView?.typingAttributes = baseTypingAttributes()
  }

  func baseTypingAttributes(block: NoteBlockKind = .paragraph) -> [NSAttributedString.Key: Any] {
    [
      .font: NoteAttributed.font(for: block, style: [], text: style), .foregroundColor: style.text,
      NoteAttr.block: block.tag, NoteAttr.indent: 0, NoteAttr.style: 0,
    ]
  }

  // MARK: Delegate

  func textDidChange(_ notification: Notification) { finishEdit() }

  func textViewDidChangeSelection(_ notification: Notification) { updateFormat() }

  func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
    switch selector {
    case #selector(NSResponder.insertNewline(_:)): return handleNewline()
    case #selector(NSResponder.deleteBackward(_:)): return handleBackspace()
    case #selector(NSResponder.insertTab(_:)): return shiftIndent(by: 1)
    case #selector(NSResponder.insertBacktab(_:)): return shiftIndent(by: -1)
    default: return false
    }
  }

  func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
    guard let url = (link as? URL) ?? (link as? String).flatMap(URL.init(string:)) else { return false }
    NSWorkspace.shared.open(url)
    return true
  }

  /// Repairs markers, restyles and publishes the Markdown after any change to the text.
  func finishEdit() {
    guard !isLoading, let view = textView, let storage = view.textStorage else { return }
    let selection = view.selectedRange()
    let edits = NoteAttributed.normalize(storage)
    NoteAttributed.restyle(storage, style: style)
    if !edits.isEmpty {
      let shift = edits.filter { $0.location < selection.location }.reduce(0) { $0 + $1.delta }
      view.setSelectedRange(NSRange(location: max(0, min(storage.length, selection.location + shift)), length: selection.length))
    }
    let markdown = NoteAttributed.markdown(from: storage)
    if markdown != lastMarkdown {
      lastMarkdown = markdown
      onMarkdownChange?(markdown)
    }
    updateFormat()
  }

  func updateFormat() {
    guard let view = textView, let storage = view.textStorage else { return }
    let selection = view.selectedRange()
    var next = Format()
    let info = lineInfo(at: selection.location)
    next.block = info?.kind ?? NoteBlockKind(tag: view.typingAttributes[NoteAttr.block] as? String)
    if selection.length > 0 {
      var common = NoteInlineStyle(rawValue: Int.max)
      var linked = true
      storage.enumerateAttributes(in: selection, options: []) { attributes, _, _ in
        common.formIntersection(NoteInlineStyle(rawValue: attributes[NoteAttr.style] as? Int ?? 0))
        if attributes[.link] == nil { linked = false }
      }
      next.inline = common.intersection([.bold, .italic, .underline, .strike, .highlight, .code])
      next.hasLink = linked
    } else {
      next.inline = NoteInlineStyle(rawValue: view.typingAttributes[NoteAttr.style] as? Int ?? 0)
      next.hasLink = view.typingAttributes[.link] != nil
    }
    if next != format { format = next }
  }

  // MARK: Lines

  struct LineInfo {
    var content: NSRange
    var kind: NoteBlockKind
    var indent: Int
    var markerLength: Int
  }

  func lineInfo(at location: Int) -> LineInfo? {
    guard let view = textView, let storage = view.textStorage else { return nil }
    let string = storage.string as NSString
    let line = string.lineRange(for: NSRange(location: min(location, string.length), length: 0))
    var content = line
    if content.length > 0, string.character(at: NSMaxRange(content) - 1) == 0x0A { content.length -= 1 }
    guard content.length > 0 else { return LineInfo(content: content, kind: .paragraph, indent: 0, markerLength: 0) }
    var kind = NoteBlockKind(tag: storage.attribute(NoteAttr.block, at: content.location, effectiveRange: nil) as? String)
    let indent = storage.attribute(NoteAttr.indent, at: content.location, effectiveRange: nil) as? Int ?? 0
    var marker = 0
    if kind.isList {
      let text = string.substring(with: content)
      if let length = NoteMarker.length(in: text, kind: kind) {
        marker = length
        if case .check = kind { kind = .check(done: text.hasPrefix(NoteMarker.checked)) }
      } else { kind = .paragraph }
    }
    return LineInfo(content: content, kind: kind, indent: indent, markerLength: marker)
  }

  private static func promptForLink(current: String?) -> String? {
    let alert = NSAlert()
    alert.messageText = L10n.tr("Add link")
    alert.addButton(withTitle: L10n.tr("Add"))
    alert.addButton(withTitle: L10n.tr("Cancel"))
    let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
    field.placeholderString = "https://"
    field.stringValue = current ?? ""
    alert.accessoryView = field
    alert.window.initialFirstResponder = field
    guard alert.runModal() == .alertFirstButtonReturn else { return nil }
    let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty else { return nil }
    return value.contains("://") || value.hasPrefix("mailto:") ? value : "https://" + value
  }
}

extension NoteEditorController {
  /// Gives the text view the keyboard again after a toolbar button was used.
  func focus() {
    guard let view = textView, let window = view.window, window.firstResponder !== view else { return }
    window.makeFirstResponder(view)
  }
}
