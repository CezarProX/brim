import SwiftUI

/// Volume slider: a slim capsule that thickens under the pointer. Past 100% (boost) the
/// fill turns orange and a tick marks 100%.
struct AudioSlider: View {
  @Binding var value: Double
  var maximum: Double = 1
  var tint: Color = .white
  var onEditingChanged: (Bool) -> Void = { _ in }
  @State private var hovering = false
  @State private var dragging = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    GeometryReader { proxy in
      let width = proxy.size.width
      let fraction = min(max(value / maximum, 0), 1)
      let thick: CGFloat = hovering || dragging ? 9 : 6
      ZStack(alignment: .leading) {
        Capsule().fill(IslandFill.raised).frame(height: thick)
        Capsule().fill(value > 1.0005 ? Color.orange : tint.opacity(0.92))
          .frame(width: max(thick, width * fraction), height: thick)
        if maximum > 1 {
          Rectangle().fill(Color.white.opacity(0.5)).frame(width: 1.5, height: thick + 4)
            .offset(x: width / maximum - 0.75)
        }
      }
      .frame(maxHeight: .infinity)
      .contentShape(Rectangle())
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged { drag in
            if !dragging { dragging = true; onEditingChanged(true) }
            var next = Double(drag.location.x / max(width, 1)) * maximum
            // A magnetic detent at 100% so boost is never entered by accident.
            if maximum > 1, abs(next - 1) < 0.04 { next = 1 }
            value = min(max(next, 0), maximum)
          }
          .onEnded { _ in dragging = false; onEditingChanged(false) })
      .onHover { hovering = $0 }
      .animation(reduceMotion ? nil : NotchMotion.feedback(reduceMotion: false), value: thick)
    }
    .frame(height: 18)
    .accessibilityElement()
    .accessibilityValue(AudioGainMath.percentLabel(value))
    .accessibilityAdjustableAction { direction in
      let step = 0.05
      value = min(max(value + (direction == .increment ? step : -step), 0), maximum)
    }
  }
}
