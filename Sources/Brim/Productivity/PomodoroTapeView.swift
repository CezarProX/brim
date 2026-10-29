import AppKit
import SwiftUI

/// Duration "tape": a horizontal detent ruler you drag; haptic ticks on each minute,
/// firmer ones on the preset detents. Value sits under the fixed marker.
struct PomodoroTapeView: View {
  @Binding var minutes: Int
  let detents: [Int]
  var tint: Color = .orange
  @State private var dragStart: Int?
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  private typealias M = PomodoroTapeMath

  var body: some View {
    Canvas { context, size in
      let center = size.width / 2
      for minute in M.visibleMinutes(centeredOn: minutes, width: size.width) {
        let x = center + M.offset(of: minute, centeredOn: minutes)
        let fade = max(0.08, 1 - abs(x - center) / center * 1.05)
        let tick = M.tick(for: minute, detents: detents)
        let height: CGFloat = tick == .detent ? 26 : tick == .major ? 18 : 11
        let color: Color = minute == minutes ? .white : tick == .detent ? tint.opacity(fade) : Color.white.opacity(0.45 * fade)
        let rect = CGRect(x: x - (tick == .detent ? 1.25 : 0.75), y: size.height - 10 - height,
                          width: tick == .detent ? 2.5 : 1.5, height: height)
        context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(color))
        if tick != .minor, minute % 5 == 0 {
          let label = context.resolve(
            Text("\(minute)").font(.system(size: 9.5, weight: .semibold)).monospacedDigit()
              .foregroundStyle(tick == .detent ? tint.opacity(fade) : Color.white.opacity(0.4 * fade)))
          context.draw(label, at: CGPoint(x: x, y: 6))
        }
      }
      var marker = Path()
      marker.move(to: CGPoint(x: center - 4, y: size.height))
      marker.addLine(to: CGPoint(x: center + 4, y: size.height))
      marker.addLine(to: CGPoint(x: center, y: size.height - 6))
      marker.closeSubpath()
      context.fill(marker, with: .color(tint))
    }
    .frame(height: 50)
    .contentShape(Rectangle())
    .gesture(
      DragGesture(minimumDistance: 0)
        .onChanged { value in
          let start = dragStart ?? minutes
          dragStart = start
          let next = M.snapped(M.rawMinutes(start: start, translation: value.translation.width), detents: detents)
          guard next != minutes else { return }
          if let tick = M.hapticTick(from: minutes, to: next, detents: detents) { Self.haptic(tick) }
          minutes = next
        }
        .onEnded { _ in dragStart = nil }
    )
    .accessibilityElement()
    .accessibilityLabel("Duration")
    .accessibilityValue(M.label(minutes: minutes))
    .accessibilityAdjustableAction { direction in
      minutes = min(M.range.upperBound, max(M.range.lowerBound, minutes + (direction == .increment ? 1 : -1)))
    }
  }

  private static func haptic(_ tick: PomodoroTapeMath.Tick) {
    NSHapticFeedbackManager.defaultPerformer.perform(tick == .detent ? .levelChange : .alignment, performanceTime: .now)
  }
}
