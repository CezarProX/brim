import SwiftUI

/// iOS-style vertical Liquid-glass slider for the screen edge. `.wide` is the pill shown on the first
/// key press, `.thin` the slimmer one for follow-up presses.
struct EdgeSliderView: View {
    let kind: EdgeSliderKind
    let level: Double
    var style: EdgeSliderSession.Style = .wide
    var tint: Color = .white
    var muted = false
    /// Called while dragging with the snapped level; nil makes the pill display-only.
    var onDrag: ((Double) -> Void)?

    static func size(for style: EdgeSliderSession.Style) -> CGSize {
        style == .wide ? CGSize(width: 64, height: 220) : CGSize(width: 30, height: 220)
    }

    private var size: CGSize { Self.size(for: style) }
    private var symbol: String {
        kind == .volume ? HUDSymbol.volume(level: level, muted: muted) : HUDSymbol.brightness(level: level)
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size.width / 2, style: .continuous)
        ZStack(alignment: .bottom) {
            shape.fill(.ultraThinMaterial)
            shape.fill(.white.opacity(0.12))
            Rectangle().fill(LinearGradient(colors: [tint.opacity(0.98), tint.opacity(0.82)], startPoint: .top, endPoint: .bottom))
                .frame(height: EdgeSliderMath.fillHeight(level: muted ? 0 : level, trackHeight: size.height))
                .frame(maxHeight: .infinity, alignment: .bottom)
                .clipShape(shape)
            Image(systemName: symbol)
                .font(.system(size: style == .wide ? 20 : 12, weight: .semibold))
                .foregroundStyle(level > 0.12 && !muted ? Color.black.opacity(0.7) : Color.white.opacity(0.85))
                .contentTransition(.symbolEffect(.replace))
                .padding(.bottom, style == .wide ? 16 : 9)
        }
        .overlay { shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.6), .white.opacity(0.08), .white.opacity(0.25)],
                                                      startPoint: .top, endPoint: .bottom), lineWidth: 0.9) }
        .frame(width: size.width, height: size.height)
        .compositingGroup()
        .shadow(color: .black.opacity(0.3), radius: 16, x: 4, y: 6)
        .contentShape(shape)
        .gesture(
            DragGesture(minimumDistance: 0).onChanged { value in
                onDrag?(EdgeSliderMath.snapped(EdgeSliderMath.level(forY: value.location.y, height: size.height), fine: false))
            }, including: onDrag == nil ? .none : .all)
        .animation(.spring(duration: 0.3, bounce: 0.15), value: style)
        .animation(.spring(duration: 0.25, bounce: 0), value: level)
        .accessibilityElement()
        .accessibilityLabel(kind == .volume ? "Volume" : "Brightness")
        .accessibilityValue("\(HUDLevelMath.percent(level)) percent")
    }
}
