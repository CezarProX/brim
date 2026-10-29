import SwiftUI

/// The formatting row: headings, bold / italic / underline, highlight, lists and a checklist. The
/// window's bar adds strikethrough, inline code and links.
struct NoteFormatBar: View {
  @ObservedObject var controller: NoteEditorController
  var full = false
  private let tint = Color(red: 1, green: 0.8, blue: 0.2)

  var body: some View {
    HStack(spacing: 2) {
      ForEach([(1, L10n.tr("Heading 1")), (2, L10n.tr("Heading 2")), (3, L10n.tr("Heading 3"))], id: \.0) { level, title in
        button(.text("H\(level)"), title, controller.format.block == .heading(level)) {
          controller.setBlock(.heading(level))
        }
      }
      divider
      button(.symbol("bold"), L10n.tr("Bold"), controller.format.inline.contains(.bold)) { controller.toggle(.bold) }
      button(.symbol("italic"), L10n.tr("Italic"), controller.format.inline.contains(.italic)) { controller.toggle(.italic) }
      button(.symbol("underline"), L10n.tr("Underline"), controller.format.inline.contains(.underline)) {
        controller.toggle(.underline)
      }
      if full {
        button(.symbol("strikethrough"), L10n.tr("Strikethrough"), controller.format.inline.contains(.strike)) {
          controller.toggle(.strike)
        }
      }
      button(.symbol("highlighter"), L10n.tr("Highlight"), controller.format.inline.contains(.highlight)) {
        controller.toggle(.highlight)
      }
      if full {
        button(.symbol("chevron.left.forwardslash.chevron.right"), L10n.tr("Code"), controller.format.inline.contains(.code)) {
          controller.toggle(.code)
        }
      }
      divider
      button(.symbol("list.bullet"), L10n.tr("Bulleted list"), controller.format.block == .bullet) { controller.setBlock(.bullet) }
      button(.symbol("list.number"), L10n.tr("Numbered list"), controller.format.block == .numbered) { controller.setBlock(.numbered) }
      button(.symbol("checklist"), L10n.tr("Checklist"), controller.format.block.sameKind(as: .check(done: false))) {
        controller.setBlock(.check(done: false))
      }
      if full {
        divider
        button(.symbol("link"), L10n.tr("Link"), controller.format.hasLink) { controller.toggleLink() }
      }
    }
  }

  private enum Face { case text(String), symbol(String) }

  private var divider: some View {
    Rectangle().fill(IslandFill.hairline).frame(width: 1, height: 14).padding(.horizontal, 3)
  }

  private func button(_ face: Face, _ help: String, _ active: Bool, _ action: @escaping () -> Void) -> some View {
    Button {
      action()
      controller.focus()
    } label: {
      Group {
        switch face {
        case .text(let value): Text(value).font(.system(size: 10.5, weight: .bold, design: .rounded))
        case .symbol(let name): Image(systemName: name).font(.system(size: 11, weight: .semibold))
        }
      }
      .foregroundStyle(active ? Color.black : IslandInk.secondary)
      .frame(width: full ? 28 : 24, height: 24)
      .background(active ? tint : Color.clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help(help)
    .accessibilityLabel(help)
  }
}
