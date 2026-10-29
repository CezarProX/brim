import SwiftUI

/// The emoji picker: search field, category strip, skin-tone menu and a keyboard-driven grid.
/// Used in a floating panel; it also fits the open island's content area.
struct EmojiPickerView: View {
  @ObservedObject var model: EmojiPickerModel
  var onClose: () -> Void = {}
  @FocusState private var searchFocused: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    VStack(spacing: IslandSpace.s) {
      header
      grid
      footer
    }
    .padding(IslandSpace.m)
    .frame(width: CGFloat(model.columns) * 38 + 2 * IslandSpace.m + 14, height: 372)
    .background(.black.opacity(0.9), in: RoundedRectangle(cornerRadius: IslandRadius.large, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: IslandRadius.large, style: .continuous).stroke(.white.opacity(0.12), lineWidth: 0.75)
    }
    .preferredColorScheme(.dark)
    .onAppear { searchFocused = true }
    .onKeyPress(.escape) { onClose(); return .handled }
    .onKeyPress(.return) { model.pickSelected(); return .handled }
    .onKeyPress(.leftArrow) { model.move(dx: -1, dy: 0); return .handled }
    .onKeyPress(.rightArrow) { model.move(dx: 1, dy: 0); return .handled }
    .onKeyPress(.upArrow) { model.move(dx: 0, dy: -1); return .handled }
    .onKeyPress(.downArrow) { model.move(dx: 0, dy: 1); return .handled }
  }

  private var header: some View {
    VStack(spacing: IslandSpace.s) {
      HStack(spacing: IslandSpace.s) {
        Image(systemName: "magnifyingglass").foregroundStyle(IslandInk.secondary)
        TextField("Search emoji", text: $model.query)
          .textFieldStyle(.plain).font(IslandFont.headline).focused($searchFocused)
          .onChange(of: model.query) { _, _ in model.queryChanged() }
        skinMenu
      }
      .padding(.horizontal, IslandSpace.m).frame(height: 32)
      .background(IslandFill.subtle, in: Capsule())
      HStack(spacing: 2) {
        categoryButton(nil, symbol: "clock")
        ForEach(EmojiCategory.allCases) { categoryButton($0, symbol: $0.symbol) }
      }
    }
  }

  private var skinMenu: some View {
    Menu {
      ForEach(EmojiSkinTone.allCases) { tone in
        Button("\(tone.swatch)  \(tone.title)") { model.setSkinTone(tone) }
      }
    } label: {
      Text(model.skinTone.swatch).font(.system(size: 15))
    }
    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
    .accessibilityLabel("Skin tone")
  }

  private func categoryButton(_ category: EmojiCategory?, symbol: String) -> some View {
    let active = model.category == category && model.query.isEmpty
    return Button {
      model.category = category
      model.query = ""
      model.selection = 0
    } label: {
      Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
        .foregroundStyle(active ? IslandInk.primary : IslandInk.tertiary)
        .frame(maxWidth: .infinity).frame(height: 26)
        .background(active ? IslandFill.raised : Color.clear, in: RoundedRectangle(cornerRadius: IslandRadius.small))
    }
    .buttonStyle(.plain)
    .accessibilityLabel(category?.title ?? "Recent")
  }

  private var grid: some View {
    let list = model.visible
    return ScrollViewReader { proxy in
      ScrollView {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(36), spacing: 2), count: model.columns), spacing: 2) {
          ForEach(Array(list.enumerated()), id: \.offset) { index, item in
            cell(item, selected: index == model.selection).id(index)
          }
        }
        .padding(.vertical, 2)
      }
      .onChange(of: model.selection) { _, value in
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) { proxy.scrollTo(value) }
      }
      .overlay {
        if list.isEmpty {
          Text("No emoji match “\(model.query)”").font(IslandFont.body).foregroundStyle(IslandInk.secondary)
        }
      }
    }
  }

  private func cell(_ item: EmojiItem, selected: Bool) -> some View {
    Button { model.pick(item) } label: {
      Text(model.display(item)).font(.system(size: 22))
        .frame(width: 36, height: 36)
        .background(selected ? IslandFill.selected : Color.clear, in: RoundedRectangle(cornerRadius: 8))
    }
    .buttonStyle(.plain)
    .accessibilityLabel(item.name)
  }

  private var footer: some View {
    let list = model.visible
    let current = list.indices.contains(model.selection) ? list[model.selection] : nil
    return HStack {
      Text(current.map { "\(model.display($0))  \($0.name)" } ?? " ")
        .font(IslandFont.label).foregroundStyle(IslandInk.secondary).lineLimit(1)
      Spacer()
      Text("Return inserts, Esc closes").font(IslandFont.caption).foregroundStyle(IslandInk.tertiary)
    }
    .frame(height: 16)
  }
}
