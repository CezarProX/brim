import AppKit
import SwiftUI

/// The launcher: a search field over ranked rows, keyboard first (arrows, Return, ⌘1-9, Esc).
struct ThunderstormView: View {
  @ObservedObject var model: ThunderstormModel
  @FocusState private var searchFocused: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  static let width: CGFloat = 640

  var body: some View {
    VStack(spacing: 0) {
      searchField
      if !model.results.isEmpty || model.notice != nil {
        Rectangle().fill(IslandFill.hairline).frame(height: 0.75)
        rows
      }
      footer
    }
    .frame(width: Self.width, height: model.panelHeight, alignment: .top)
    .background { glass }
    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    .overlay { RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.white.opacity(0.14), lineWidth: 0.75) }
    .preferredColorScheme(.dark)
    .onAppear { searchFocused = true }
    .onKeyPress(.escape) { model.onDismiss(); return .handled }
    .onKeyPress(.downArrow) { model.move(1); return .handled }
    .onKeyPress(.upArrow) { model.move(-1); return .handled }
    .onKeyPress(.return) { model.activateSelected(); return .handled }
    .onKeyPress(phases: .down) { press in
      guard press.modifiers == .command else { return .ignored }
      if press.characters == "c" { model.copyTitleOfSelected(); return .handled }
      if let digit = Int(press.characters), (1...9).contains(digit) { model.activate(index: digit - 1); return .handled }
      return .ignored
    }
    .animation(reduceMotion ? nil : .smooth(duration: 0.18), value: model.results.count)
  }

  private var glass: some View {
    ZStack {
      Rectangle().fill(.ultraThinMaterial)
      Rectangle().fill(Color.black.opacity(0.78))
      LinearGradient(colors: [.white.opacity(0.07), .clear], startPoint: .top, endPoint: .center)
    }
  }

  private var searchField: some View {
    HStack(spacing: 12) {
      Image(systemName: "bolt.fill")
        .font(.system(size: 17, weight: .semibold))
        .foregroundStyle(LinearGradient(colors: [Color(red: 0.7, green: 0.6, blue: 1), Color(red: 0.45, green: 0.4, blue: 1)], startPoint: .top, endPoint: .bottom))
      TextField("Search apps, files, clipboard, math…", text: $model.query)
        .textFieldStyle(.plain).font(.system(size: 20, weight: .regular)).focused($searchFocused)
        .onSubmit { model.activateSelected() }
      if !model.query.isEmpty {
        Button { model.query = "" } label: {
          Image(systemName: "xmark.circle.fill").foregroundStyle(IslandInk.tertiary)
        }
        .buttonStyle(.plain).accessibilityLabel("Clear")
      }
    }
    .padding(.horizontal, 20).frame(height: 62)
  }

  private var rows: some View {
    VStack(spacing: 2) {
      ForEach(Array(model.results.enumerated()), id: \.element.id) { index, result in
        ThunderRow(
          result: result, index: index, selected: index == model.selection,
          confirming: model.confirming?.id == result.id
        )
        .onTapGesture { model.activate(result) }
        .onHover { inside in if inside { model.selection = index } }
      }
      if let notice = model.notice {
        Text(notice).font(IslandFont.label).foregroundStyle(.orange).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14)
      }
    }
    .padding(.horizontal, 8).padding(.vertical, 7)
  }

  private var footer: some View {
    HStack(spacing: 14) {
      hint("↩", model.confirming != nil ? "Confirm" : (model.results.indices.contains(model.selection) ? model.results[model.selection].hint : "Open"))
      hint("⌘C", "Copy")
      hint("⌘1–9", "Quick pick")
      Spacer()
      hint("esc", "Close")
    }
    .font(IslandFont.caption).foregroundStyle(IslandInk.tertiary)
    .padding(.horizontal, 20).frame(height: 30)
    .background(Color.black.opacity(0.25))
  }

  private func hint(_ key: String, _ label: String) -> some View {
    HStack(spacing: 5) {
      Text(key).font(.system(size: 10, weight: .semibold, design: .rounded))
        .padding(.horizontal, 5).padding(.vertical, 1.5)
        .background(IslandFill.raised, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
      Text(label)
    }
  }
}

struct ThunderRow: View {
  let result: ThunderResult
  let index: Int
  let selected: Bool
  let confirming: Bool

  var body: some View {
    HStack(spacing: 12) {
      icon.frame(width: 30, height: 30)
      VStack(alignment: .leading, spacing: 1) {
        Text(confirming ? "Press Return again to \(result.title.lowercased())" : result.title)
          .font(result.kind == .calculator || result.kind == .conversion ? .system(size: 18, weight: .semibold, design: .rounded) : .system(size: 14, weight: .medium))
          .foregroundStyle(confirming ? Color.orange : IslandInk.primary).lineLimit(1)
        if !result.subtitle.isEmpty {
          Text(result.subtitle).font(IslandFont.label).foregroundStyle(IslandInk.secondary).lineLimit(1)
        }
      }
      Spacer(minLength: 8)
      if selected {
        Text(result.hint).font(IslandFont.label).foregroundStyle(IslandInk.secondary)
      }
      if index < 9 {
        Text("⌘\(index + 1)").font(.system(size: 10, weight: .semibold, design: .rounded)).foregroundStyle(IslandInk.tertiary)
          .frame(width: 26)
      }
    }
    .padding(.horizontal, 10).frame(height: 44)
    .background(selected ? IslandFill.raised : Color.clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    .contentShape(Rectangle())
  }

  @ViewBuilder private var icon: some View {
    if let path = result.iconPath, result.kind == .app || result.kind == .file {
      Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().interpolation(.high)
    } else {
      let colors = Self.colors(result.kind)
      ZStack {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
        Image(systemName: result.symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
      }
    }
  }

  private static func colors(_ kind: ThunderResult.Kind) -> [Color] {
    switch kind {
    case .calculator, .conversion: [Color(red: 1, green: 0.62, blue: 0.25), Color(red: 0.95, green: 0.42, blue: 0.1)]
    case .clipboard: [Color(red: 0.4, green: 0.8, blue: 0.8), Color(red: 0.2, green: 0.6, blue: 0.65)]
    case .quicklink, .web: [Color(red: 0.4, green: 0.7, blue: 1), Color(red: 0.2, green: 0.45, blue: 0.95)]
    case .snippet: [Color(red: 0.75, green: 0.55, blue: 1), Color(red: 0.55, green: 0.35, blue: 0.95)]
    case .system: [Color(red: 0.6, green: 0.6, blue: 0.66), Color(red: 0.38, green: 0.38, blue: 0.44)]
    case .app, .file: [Color(white: 0.5), Color(white: 0.3)]
    }
  }
}
