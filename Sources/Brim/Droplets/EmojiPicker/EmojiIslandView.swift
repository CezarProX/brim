import AppKit
import SwiftUI

/// The emoji picker inside the island: type to search, arrows and Return to choose, or click.
/// The emoji is pasted into the app you were using when the island opened.
@MainActor
struct EmojiIslandView: View {
  @StateObject private var model = EmojiPickerModel(columns: EmojiIslandView.columns)
  @State private var target: NSRunningApplication?
  @State private var trusted = AXIsProcessTrusted()
  @State private var hovered: Int?
  @FocusState private var searchFocused: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  static let columns = 12
  private let onInserted: (() -> Void)?

  init(onInserted: (() -> Void)? = nil) {
    self.onInserted = onInserted
  }

  var body: some View {
    VStack(spacing: 8) {
      IslandSearchField(prompt: L10n.tr("Search emoji"), text: $model.query, focus: $searchFocused) { skinMenu }
        .onChange(of: model.query) { _, _ in model.queryChanged(); hovered = nil }
      categoryStrip
      grid
      footer.frame(height: 28)
    }
    .onAppear {
      target = EmojiInserter.frontTarget()
      trusted = AXIsProcessTrusted()
      searchFocused = true
      model.onPick = { character in
        if let onInserted { onInserted() } else { NotchShelfController.shared.dismissShelf() }
        EmojiInserter.insert(character, into: target, trusted: trusted)
      }
    }
    .onKeyPress(.return) { model.pickSelected(); return .handled }
    .onKeyPress(.leftArrow) { model.move(dx: -1, dy: 0); return .handled }
    .onKeyPress(.rightArrow) { model.move(dx: 1, dy: 0); return .handled }
    .onKeyPress(.upArrow) { model.move(dx: 0, dy: -1); return .handled }
    .onKeyPress(.downArrow) { model.move(dx: 0, dy: 1); return .handled }
  }

  private var skinMenu: some View {
    Menu {
      ForEach(EmojiSkinTone.allCases) { tone in
        Button("\(tone.swatch)  \(tone.title)") { model.setSkinTone(tone) }
      }
    } label: {
      Text(model.skinTone.swatch).font(.system(size: 16)).frame(width: 28, height: 28)
    }
    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
    .help("Skin tone").accessibilityLabel("Skin tone")
  }

  private var categoryStrip: some View {
    HStack(spacing: 2) {
      categoryButton(nil, symbol: "clock", title: L10n.tr("Recent"))
      ForEach(EmojiCategory.allCases) { categoryButton($0, symbol: $0.symbol, title: $0.title) }
    }
  }

  private func categoryButton(_ category: EmojiCategory?, symbol: String, title: String) -> some View {
    let active = model.category == category && model.query.isEmpty
    return Button {
      model.category = category
      model.query = ""
      model.selection = 0
    } label: {
      Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
        .foregroundStyle(active ? IslandInk.primary : IslandInk.tertiary)
        .frame(maxWidth: .infinity).frame(height: 28)
        .background(active ? IslandFill.raised : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain).help(title).accessibilityLabel(title)
  }

  private var grid: some View {
    let list = model.visible
    return ScrollViewReader { proxy in
      ScrollView {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: Self.columns), spacing: 2) {
          ForEach(Array(list.enumerated()), id: \.offset) { index, item in
            cell(item, index: index).id(index)
          }
        }
      }
      .scrollIndicators(.hidden)
      .onChange(of: model.selection) { _, value in
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) { proxy.scrollTo(value) }
      }
      .overlay {
        if list.isEmpty {
          IslandEmptyNote(symbol: "magnifyingglass", text: L10n.tr("No emoji match “%@”.", model.query))
        }
      }
    }
  }

  private func cell(_ item: EmojiItem, index: Int) -> some View {
    Button { model.pick(item) } label: {
      Text(model.display(item)).font(.system(size: 23))
        .frame(maxWidth: .infinity).frame(height: 34)
        .background(
          index == model.selection ? IslandFill.selected : (hovered == index ? IslandFill.subtle : Color.clear),
          in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { inside in if inside { hovered = index } else if hovered == index { hovered = nil } }
    .accessibilityLabel(item.name)
  }

  private var footer: some View {
    let list = model.visible
    let index = hovered ?? model.selection
    let current = list.indices.contains(index) ? list[index] : nil
    return HStack(spacing: 10) {
      if let current {
        Text(model.display(current)).font(.system(size: 20))
        Text(current.displayName).font(.system(size: 12.5, weight: .medium)).foregroundStyle(IslandInk.secondary).lineLimit(1)
      }
      Spacer(minLength: 6)
      if trusted {
        Text(target?.localizedName.map { L10n.tr("Return inserts into %@", $0) } ?? L10n.tr("Return copies the emoji"))
          .font(.system(size: 12)).foregroundStyle(IslandInk.tertiary).lineLimit(1)
      } else {
        Text("Only copies for now").font(.system(size: 12)).foregroundStyle(Color.orange).lineLimit(1)
        Button("Allow pasting") { SelectionReader.requestTrust() }
          .buttonStyle(IslandPillStyle(prominent: true, tint: .orange, compact: true))
      }
    }
  }
}
