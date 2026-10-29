import SwiftUI

/// Renders markdown-lite blocks; checkboxes toggle the underlying text.
struct MarkdownPreview: View {
  let text: String
  let toggle: (Int) -> Void

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 3) {
        ForEach(Array(MarkdownLite.blocks(text).enumerated()), id: \.offset) { index, block in
          row(block, line: index)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .scrollIndicators(.hidden)
  }

  @ViewBuilder private func row(_ block: MarkdownBlock, line: Int) -> some View {
    switch block {
    case .heading(let level, let text):
      Text(MarkdownLite.inline(text)).font(.system(size: level == 1 ? 15 : level == 2 ? 13 : 12, weight: .bold))
        .padding(.top, level == 1 ? 2 : 4)
    case .bullet(let text):
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        Text("•").foregroundStyle(IslandInk.tertiary)
        Text(MarkdownLite.inline(text))
      }.font(IslandFont.body)
    case .checkbox(let done, let text):
      Button { toggle(line) } label: {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
          Image(systemName: done ? "checkmark.circle.fill" : "circle")
            .foregroundStyle(done ? Color.yellow : IslandInk.secondary)
          Text(MarkdownLite.inline(text)).strikethrough(done).foregroundStyle(done ? IslandInk.tertiary : IslandInk.primary)
        }
        .font(IslandFont.body).contentShape(Rectangle())
      }
      .buttonStyle(.plain)
    case .quote(let text):
      HStack(spacing: 6) {
        Capsule().fill(IslandInk.tertiary).frame(width: 2)
        Text(MarkdownLite.inline(text)).foregroundStyle(IslandInk.secondary)
      }.font(IslandFont.body).fixedSize(horizontal: false, vertical: true)
    case .code(let text):
      Text(text.isEmpty ? " " : text).font(.system(size: 11, design: .monospaced)).foregroundStyle(IslandInk.secondary)
        .padding(.horizontal, 6).frame(maxWidth: .infinity, alignment: .leading).background(IslandFill.subtle)
    case .paragraph(let text):
      Text(MarkdownLite.inline(text)).font(IslandFont.body)
    case .blank:
      Color.clear.frame(height: 4)
    }
  }
}
