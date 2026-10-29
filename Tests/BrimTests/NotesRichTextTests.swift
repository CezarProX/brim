import AppKit
import Testing

@testable import Brim

/// Markdown <-> styled text for every formatting the notes editor offers.
@Suite("Notes rich text")
struct NotesRichTextTests {
  private func roundTrip(_ markdown: String) -> String {
    NoteMarkdown.serialize(NoteMarkdown.parse(markdown))
  }

  private func viaAttributed(_ markdown: String) -> String {
    NoteAttributed.markdown(from: NoteAttributed.attributed(markdown: markdown, style: .island))
  }

  @Test(arguments: [
    "plain text", "# One", "## Two", "### Three", "- bullet", "1. first\n2. second", "- [ ] todo", "- [x] done", "> quoted",
    "**bold** text", "*italic* text", "<u>under</u>line", "~~gone~~", "==marked==", "use `code` here", "see [docs](https://a.b/c)",
    "**bold *and italic* mix**", "[**bold link**](https://x.y)", "a\n\nb\n", "```\nlet x = 1\n\nlet y = 2\n```",
    "  - nested", "- [ ] **Record** the demo", "# Title with *style*",
  ])
  func markdownSurvivesTheModel(_ markdown: String) {
    #expect(roundTrip(markdown) == markdown)
    #expect(viaAttributed(markdown) == markdown)
  }

  @Test func adjacentBoldAndItalicDoNotMerge() {
    #expect(roundTrip("**bold**_x_") == "**bold***x*")
    #expect(NoteMarkdown.parse("**bold***x*") == NoteMarkdown.parse("**bold**_x_"))
  }

  @Test func everyInlineStyleParsesToItsFlag() {
    let cases: [(String, NoteInlineStyle)] = [
      ("**a**", .bold), ("*a*", .italic), ("_a_", .italic), ("<u>a</u>", .underline), ("~~a~~", .strike),
      ("==a==", .highlight), ("`a`", .code),
    ]
    for (markdown, flag) in cases {
      let runs = NoteInlineMarkdown.parse(markdown)
      #expect(runs == [NoteRun(text: "a", style: flag)], "\(markdown)")
    }
    #expect(NoteInlineMarkdown.parse("[a](https://x.y)") == [NoteRun(text: "a", style: [], link: "https://x.y")])
  }

  @Test func blocksParseToTheirKinds() {
    let kinds = NoteMarkdown.parse("# a\n## b\n### c\n- d\n1. e\n- [ ] f\n- [x] g\n> h\ni").map(\.kind)
    #expect(kinds == [.heading(1), .heading(2), .heading(3), .bullet, .numbered, .check(done: false), .check(done: true), .quote, .paragraph])
  }

  @Test func legacyMarkersAreNormalisedNotLost() {
    #expect(roundTrip("* star\n+ plus\n* [X] done") == "- star\n- plus\n- [x] done")
    #expect(roundTrip("3. a\n4. b") == "1. a\n2. b")
  }

  @Test func unclosedAndSpacedDelimitersStayLiteral() {
    for text in ["2 * 3 * 4", "a ** b", "snake_case_name", "[ ] not a link", "5 == 5", "**open only", "~~x"] {
      #expect(NoteInlineMarkdown.parse(text).allSatisfy { $0.style.isEmpty && $0.link == nil }, "\(text)")
      #expect(NoteMarkdown.parse(roundTrip(text)) == NoteMarkdown.parse(text), "\(text)")
    }
    for text in ["2 * 3 * 4", "a ** b", "snake_case_name", "[ ] not a link", "5 == 5"] { #expect(roundTrip(text) == text) }
  }

  @Test func literalDelimitersTypedByTheUserAreEscapedSoTheyStayLiteral() {
    for text in ["a*b*c", "x`y`z", "1. not a list", "- not a bullet", "# not a heading", "> not a quote", "[a](b)", "<u>raw</u>"] {
      let line = NoteLine(kind: .paragraph, runs: [NoteRun(text: text)])
      let written = NoteMarkdown.serialize([line])
      #expect(NoteMarkdown.parse(written) == [line], "\(text) -> \(written)")
    }
  }

  @Test func styledRunsNeverHugWhitespaceDelimiters() {
    let line = NoteLine(runs: [NoteRun(text: "say "), NoteRun(text: " hello ", style: .bold), NoteRun(text: "there")])
    let written = NoteMarkdown.serialize([line])
    #expect(written == "say  **hello** there")
    #expect(NoteMarkdown.parse(written)[0].runs.contains(NoteRun(text: "hello", style: .bold)))
  }

  @Test func nestedStylesWriteAndReadBack() {
    let runs = [
      NoteRun(text: "a", style: .bold), NoteRun(text: "b", style: [.bold, .italic]), NoteRun(text: "c", style: .italic),
      NoteRun(text: "d", style: [.bold, .underline, .highlight]), NoteRun(text: "e", style: .code),
    ]
    let line = NoteLine(runs: runs)
    #expect(NoteMarkdown.parse(NoteMarkdown.serialize([line])) == [line])
  }

  @Test func codeSpansKeepBackticksAndFences() {
    let line = NoteLine(runs: [NoteRun(text: "a`b", style: .code)])
    #expect(NoteMarkdown.parse(NoteMarkdown.serialize([line])) == [line])
    let block = NoteMarkdown.parse("```\n*not bold*\n```")
    #expect(block.map(\.kind) == [.code])
    #expect(block[0].runs == [NoteRun(text: "*not bold*")])
  }

  @Test func attributedTextCarriesMarkersAndNumbers() {
    let text = NoteAttributed.attributed(markdown: "- a\n1. b\n2. c\n- [x] d", style: .island)
    #expect(text.string == "\u{2022} a\n1. b\n2. c\n\u{2611} d")
    #expect(text.attribute(NoteAttr.block, at: 0, effectiveRange: nil) as? String == "ul")
  }

  @Test func displayAttributesFollowTheSemanticOnes() {
    let text = NoteAttributed.attributed(markdown: "# Big\n**b** ==h== ~~s~~ <u>u</u>", style: .island)
    let heading = text.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
    #expect((heading?.pointSize ?? 0) > 18)
    let secondLine = (text.string as NSString).range(of: "b")
    #expect(((text.attribute(.font, at: secondLine.location, effectiveRange: nil) as? NSFont)?.fontDescriptor.symbolicTraits.contains(.bold)) == true)
    let h = (text.string as NSString).range(of: "h")
    #expect(text.attribute(.backgroundColor, at: h.location, effectiveRange: nil) != nil)
    let s = (text.string as NSString).range(of: "s")
    #expect(text.attribute(.strikethroughStyle, at: s.location, effectiveRange: nil) != nil)
    let u = (text.string as NSString).range(of: "u")
    #expect(text.attribute(.underlineStyle, at: u.location, effectiveRange: nil) != nil)
    // The display strikethrough on a ticked item is not written back as ~~.
    #expect(NoteAttributed.markdown(from: NoteAttributed.attributed(markdown: "- [x] done", style: .island)) == "- [x] done")
  }

  @Test func normalizeRenumbersAndRepairsDamagedMarkers() {
    let text = NoteAttributed.attributed(markdown: "1. a\n2. b\n3. c", style: .island)
    text.replaceCharacters(in: NSRange(location: 0, length: 3), with: "")  // delete the first item's marker
    NoteAttributed.normalize(text)
    #expect(text.string == "a\n1. b\n2. c")
    #expect(NoteAttributed.markdown(from: text) == "a\n1. b\n2. c")
  }
}

/// The editor controller driving a real text view.
@MainActor
@Suite("Notes editor controller")
struct NotesEditorControllerTests {
  private func make(_ markdown: String) -> (NoteEditorController, NoteTextView, () -> String) {
    let view = NoteTextView.make(style: .island)
    view.frame = NSRect(x: 0, y: 0, width: 300, height: 200)
    let controller = NoteEditorController()
    controller.attach(view, style: .island)
    controller.load(markdown: markdown)
    var latest = markdown
    controller.onMarkdownChange = { latest = $0 }
    return (controller, view, { latest })
  }

  @Test func boldAppliesToTheSelectionAndTogglesOff() {
    let (controller, view, out) = make("hello world")
    view.setSelectedRange(NSRange(location: 0, length: 5))
    controller.toggle(.bold)
    #expect(out() == "**hello** world")
    #expect(controller.format.inline.contains(.bold))
    controller.toggle(.bold)
    #expect(out() == "hello world")
  }

  @Test func eachInlineButtonWritesItsMarkdown() {
    let expected: [(NoteInlineStyle, String)] = [
      (.italic, "*hi*"), (.underline, "<u>hi</u>"), (.strike, "~~hi~~"), (.highlight, "==hi=="), (.code, "`hi`"),
    ]
    for (flag, markdown) in expected {
      let (controller, view, out) = make("hi")
      view.setSelectedRange(NSRange(location: 0, length: 2))
      controller.toggle(flag)
      #expect(out() == markdown)
    }
  }

  @Test func blockButtonsConvertAndRevertLines() {
    let kinds: [(NoteBlockKind, String)] = [
      (.heading(1), "# one\ntwo"), (.heading(2), "## one\ntwo"), (.heading(3), "### one\ntwo"), (.bullet, "- one\ntwo"),
      (.numbered, "1. one\ntwo"), (.check(done: false), "- [ ] one\ntwo"),
    ]
    for (kind, markdown) in kinds {
      let (controller, view, out) = make("one\ntwo")
      view.setSelectedRange(NSRange(location: 1, length: 0))
      controller.setBlock(kind)
      #expect(out() == markdown)
      controller.setBlock(kind)
      #expect(out() == "one\ntwo", "toggling \(kind) off")
    }
  }

  @Test func numberedListRenumbersWhenALineIsInserted() {
    let (controller, view, out) = make("a\nb\nc")
    view.setSelectedRange(NSRange(location: 0, length: 5))
    controller.setBlock(.numbered)
    #expect(out() == "1. a\n2. b\n3. c")
  }

  @Test func clickingAChecklistMarkerTogglesIt() {
    let (controller, _, out) = make("- [ ] task")
    controller.toggleChecklist(at: 0)
    #expect(out() == "- [x] task")
    controller.toggleChecklist(at: 0)
    #expect(out() == "- [ ] task")
  }

  @Test func enterContinuesAListAndLeavesItWhenEmpty() {
    let (controller, view, out) = make("- one")
    view.setSelectedRange(NSRange(location: view.string.utf16.count, length: 0))
    #expect(controller.handleNewline())
    view.insertText("two", replacementRange: view.selectedRange())
    #expect(out() == "- one\n- two")
    #expect(controller.handleNewline())
    #expect(controller.handleNewline())
    #expect(out() == "- one\n- two\n")
  }

  @Test func backspaceAtTheStartOfAnItemLeavesTheList() {
    let (controller, view, out) = make("- one")
    view.setSelectedRange(NSRange(location: 2, length: 0))
    #expect(controller.handleBackspace())
    #expect(out() == "one")
  }

  @Test func linkButtonWrapsTheSelection() {
    let (controller, view, out) = make("see docs")
    controller.requestLink = { _ in "https://example.com" }
    view.setSelectedRange(NSRange(location: 4, length: 4))
    controller.toggleLink()
    #expect(out() == "see [docs](https://example.com)")
    controller.toggleLink()
    #expect(out() == "see docs")
  }

  @Test func pastedMarkdownArrivesFormatted() {
    let (controller, view, out) = make("")
    controller.insert(markdown: "# Title\n- a\n- b")
    #expect(out() == "# Title\n- a\n- b")
    #expect(view.string.contains("\u{2022} a"))
  }

  @Test func externalChangesReloadButOwnEditsDoNot() {
    let (controller, view, _) = make("one")
    view.setSelectedRange(NSRange(location: 3, length: 0))
    controller.loadIfChanged(markdown: "one")
    #expect(view.selectedRange().location == 3)
    controller.loadIfChanged(markdown: "two")
    #expect(view.string == "two")
  }
}
