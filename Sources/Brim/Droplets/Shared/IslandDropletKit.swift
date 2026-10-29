import SwiftUI

// Small building blocks shared by the apps that live inside the island (Emoji Picker, Launcher,
// Cleaner, Menu Bar): a search field, a two-way switcher, a first-run card, and a hover row.

/// A rounded search field in the island's own language (capsule, 12 pt+ text, 32 pt tall).
struct IslandSearchField<Trailing: View>: View {
  let prompt: String
  @Binding var text: String
  var font: Font = .system(size: 14)
  var height: CGFloat = 34
  var focus: FocusState<Bool>.Binding
  @ViewBuilder var trailing: Trailing

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: "magnifyingglass").font(.system(size: 13, weight: .semibold)).foregroundStyle(IslandInk.secondary)
      TextField(prompt, text: $text).textFieldStyle(.plain).font(font).focused(focus)
      if !text.isEmpty {
        Button { text = "" } label: {
          Image(systemName: "xmark.circle.fill").font(.system(size: 13)).foregroundStyle(IslandInk.tertiary)
            .frame(width: 28, height: 28).contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityLabel("Clear").help("Clear")
      }
      trailing
    }
    .padding(.leading, 12).padding(.trailing, 6).frame(height: height)
    .background(IslandFill.subtle, in: Capsule())
    .overlay { Capsule().strokeBorder(IslandFill.hairline, lineWidth: 0.75) }
  }
}

extension IslandSearchField where Trailing == EmptyView {
  init(prompt: String, text: Binding<String>, font: Font = .system(size: 14), height: CGFloat = 34, focus: FocusState<Bool>.Binding) {
    self.init(prompt: prompt, text: text, font: font, height: height, focus: focus) { EmptyView() }
  }
}

/// Two or three options in one capsule, like a segmented control that matches the island.
struct IslandSegmented<Value: Hashable>: View {
  let options: [(value: Value, title: String)]
  let selection: Value
  let select: (Value) -> Void
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Namespace private var thumb

  var body: some View {
    HStack(spacing: 2) {
      ForEach(options, id: \.value) { option in
        let active = option.value == selection
        Button { select(option.value) } label: {
          Text(option.title).font(.system(size: 12, weight: .semibold))
            .foregroundStyle(active ? IslandInk.primary : IslandInk.secondary)
            .padding(.horizontal, 14).frame(height: 28).contentShape(Capsule())
            .background {
              if active { Capsule().fill(IslandFill.selected).matchedGeometryEffect(id: "thumb", in: thumb) }
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
      }
    }
    .padding(2).background(IslandFill.subtle, in: Capsule())
    .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: selection)
  }
}

/// First-run card: what the app does, what it will touch, and ONE button that turns it on.
struct IslandIntroCard: View {
  let symbol: String
  let tint: Color
  let headline: String
  let lines: [(symbol: String, text: String)]
  let actionTitle: String
  let action: () -> Void
  var footnote: String?

  var body: some View {
    HStack(alignment: .center, spacing: 22) {
      ZStack {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
          .fill(LinearGradient(colors: [tint.opacity(0.95), tint.opacity(0.62)], startPoint: .top, endPoint: .bottom))
        Image(systemName: symbol).font(.system(size: 38, weight: .semibold)).foregroundStyle(.white)
      }
      .frame(width: 84, height: 84)
      .shadow(color: tint.opacity(0.35), radius: 12, y: 4)
      .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 8) {
        Text(headline).font(.system(size: 16, weight: .semibold)).foregroundStyle(IslandInk.primary)
          .fixedSize(horizontal: false, vertical: true)
        VStack(alignment: .leading, spacing: 5) {
          ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
            HStack(alignment: .firstTextBaseline, spacing: 8) {
              Image(systemName: line.symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(tint)
                .frame(width: 16)
              Text(line.text).font(.system(size: 12.5)).foregroundStyle(IslandInk.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
          }
        }
        HStack(spacing: 12) {
          Button(action: action) { Text(actionTitle) }
            .buttonStyle(IslandPillStyle(prominent: true, tint: tint))
          if let footnote {
            Text(footnote).font(.system(size: 12)).foregroundStyle(IslandInk.tertiary)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
        .padding(.top, 2)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.horizontal, 6)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

/// Row chrome with a hover highlight and an optional selected state.
struct IslandHoverRow<Content: View>: View {
  var selected = false
  var height: CGFloat = 40
  @ViewBuilder var content: Content
  @State private var hovered = false

  var body: some View {
    content
      .padding(.horizontal, 10).frame(height: height)
      .background(
        selected ? IslandFill.raised : (hovered ? IslandFill.subtle : Color.clear),
        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
      )
      .contentShape(Rectangle())
      .onHover { hovered = $0 }
  }
}

/// A centered note for empty and loading states.
struct IslandEmptyNote: View {
  let symbol: String
  let text: String
  var spinner = false

  var body: some View {
    VStack(spacing: 8) {
      if spinner { ProgressView().controlSize(.small) } else {
        Image(systemName: symbol).font(.system(size: 22, weight: .light)).foregroundStyle(IslandInk.tertiary)
      }
      Text(text).font(.system(size: 12.5)).foregroundStyle(IslandInk.secondary).multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

extension View {
  /// Softens the bottom edge of a scrolling list so a row is never cut off hard.
  func islandBottomFade(_ height: CGFloat = 16) -> some View {
    mask(
      VStack(spacing: 0) {
        Rectangle().fill(Color.black)
        LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: height)
      })
  }
}
