import SwiftUI

/// Single-line text that glides sideways only when it does not fit ("Scroll long names").
/// Short text is plain, static text; no timeline runs for it.
struct MarqueeText: View {
  let text: String
  var font: Font
  var color: Color = IslandInk.primary
  var tracking: CGFloat = 0
  /// nil reads the user's "Scroll long names" setting.
  var enabled: Bool?
  @State private var textWidth: CGFloat = 0
  @State private var containerWidth: CGFloat = 0
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var started = Date()

  private var scrolls: Bool {
    !reduceMotion
      && MarqueePolicy.needsScroll(textWidth: textWidth, containerWidth: containerWidth,
                                   enabled: enabled ?? AppSettings.shared.scrollLongNames)
  }

  var body: some View {
    label
      .lineLimit(1)
      .frame(maxWidth: .infinity, alignment: .leading)
      .opacity(scrolls ? 0 : 1)
      .overlay(alignment: .leading) { if scrolls { scrolling } }
      .background(alignment: .leading) {
        label.fixedSize().hidden()
          .background(GeometryReader { Color.clear.preference(key: WidthKey.self, value: $0.size.width) })
      }
      .background(GeometryReader { Color.clear.preference(key: ContainerKey.self, value: $0.size.width) })
      .onPreferenceChange(WidthKey.self) { textWidth = $0 }
      .onPreferenceChange(ContainerKey.self) { containerWidth = $0 }
      .onChange(of: text) { _, _ in started = Date() }
      .clipped()
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(text)
  }

  private var label: some View {
    Text(text).font(font).tracking(tracking).foregroundStyle(color)
  }

  private var scrolling: some View {
    TimelineView(.animation) { context in
      let offset = MarqueePolicy.offset(at: context.date.timeIntervalSince(started), textWidth: textWidth)
      HStack(spacing: MarqueePolicy.gap) {
        label.fixedSize()
        label.fixedSize()
      }
      .offset(x: offset)
      // The leading edge only fades once text has moved under it.
      .mask(
        LinearGradient(stops: [.init(color: offset < -1 ? .clear : .black, location: 0),
                               .init(color: .black, location: 0.05),
                               .init(color: .black, location: 0.94), .init(color: .clear, location: 1)],
                       startPoint: .leading, endPoint: .trailing))
    }
  }
}

private struct WidthKey: PreferenceKey {
  static let defaultValue: CGFloat = 0
  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct ContainerKey: PreferenceKey {
  static let defaultValue: CGFloat = 0
  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
