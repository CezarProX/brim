import AppKit
import SwiftUI

/// A TextKit 1 text view whose list markers are clickable (checklist items toggle on click).
final class NoteTextView: NSTextView {
  var toggleChecklist: ((Int) -> Void)?

  static func make(style: NoteTextStyle) -> NoteTextView {
    let storage = NSTextStorage()
    let layout = NSLayoutManager()
    let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
    container.widthTracksTextView = true
    storage.addLayoutManager(layout)
    layout.addTextContainer(container)
    let view = NoteTextView(frame: .zero, textContainer: container)
    view.isRichText = true
    view.allowsUndo = true
    view.drawsBackground = false
    view.isVerticallyResizable = true
    view.isHorizontallyResizable = false
    view.autoresizingMask = [.width]
    view.textContainerInset = NSSize(width: 4, height: 6)
    view.insertionPointColor = style.accent
    view.isAutomaticQuoteSubstitutionEnabled = false
    view.isAutomaticDashSubstitutionEnabled = false
    view.isAutomaticLinkDetectionEnabled = true
    view.linkTextAttributes = [.foregroundColor: style.link, .underlineStyle: NSUnderlineStyle.single.rawValue]
    view.selectedTextAttributes = [.backgroundColor: NSColor(white: 1, alpha: 0.22)]
    view.usesFontPanel = false
    return view
  }

  override func mouseDown(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)
    if let index = checklistMarkerIndex(at: point) {
      toggleChecklist?(index)
      return
    }
    super.mouseDown(with: event)
  }

  /// Start of the checklist marker under `point`, if there is one.
  private func checklistMarkerIndex(at point: NSPoint) -> Int? {
    guard let layout = layoutManager, let container = textContainer, textStorage?.length ?? 0 > 0 else { return nil }
    let local = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
    let glyph = layout.glyphIndex(for: local, in: container)
    let character = layout.characterIndexForGlyph(at: glyph)
    let string = string as NSString
    let line = string.lineRange(for: NSRange(location: character, length: 0))
    guard line.length >= 2, let kind = textStorage?.attribute(NoteAttr.block, at: line.location, effectiveRange: nil) as? String,
      kind == NoteBlockKind.check(done: false).tag,
      string.substring(with: NSRange(location: line.location, length: 1)) == "\u{2610}"
        || string.substring(with: NSRange(location: line.location, length: 1)) == "\u{2611}"
    else { return nil }
    let marker = layout.boundingRect(forGlyphRange: layout.glyphRange(forCharacterRange: NSRange(location: line.location, length: 1), actualCharacterRange: nil), in: container)
    return marker.insetBy(dx: -6, dy: -3).contains(local) ? line.location : nil
  }

  /// Pasted text is read as Markdown so copied lists, headings and links arrive formatted.
  override func paste(_ sender: Any?) {
    guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty, let controller = delegate as? NoteEditorController
    else { return super.paste(sender) }
    controller.insert(markdown: text)
  }

  override func pasteAsPlainText(_ sender: Any?) {
    guard let text = NSPasteboard.general.string(forType: .string) else { return }
    insertText(text, replacementRange: selectedRange())
  }

}

/// SwiftUI host for the rich note editor. Reading and writing go through Markdown.
struct NoteRichEditor: NSViewRepresentable {
  @Binding var markdown: String
  let controller: NoteEditorController
  var style: NoteTextStyle
  var autofocus = false

  func makeNSView(context: Context) -> NSScrollView {
    let textView = NoteTextView.make(style: style)
    let scroll = NSScrollView()
    scroll.documentView = textView
    scroll.drawsBackground = false
    scroll.hasVerticalScroller = true
    scroll.autohidesScrollers = true
    scroll.scrollerStyle = .overlay
    scroll.borderType = .noBorder
    controller.attach(textView, style: style)
    controller.load(markdown: markdown)
    controller.onMarkdownChange = { markdown = $0 }
    if autofocus {
      DispatchQueue.main.async { textView.window?.makeFirstResponder(textView) }
    }
    return scroll
  }

  func updateNSView(_ scroll: NSScrollView, context: Context) {
    controller.onMarkdownChange = { markdown = $0 }
    controller.setStyle(style)
    controller.loadIfChanged(markdown: markdown)
  }
}
