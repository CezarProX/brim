import AppKit
import SwiftUI

/// Pure mapping between drag distance and minutes, kept separate so it can be tested.
enum TimerDialMath {
  static let spacing: CGFloat = 9

  /// Minutes after dragging `translation` points from `start`; dragging left increases.
  static func minutes(from start: Int, translation: CGFloat, range: ClosedRange<Int>) -> Int {
    let delta = Int((-translation / spacing).rounded())
    return min(range.upperBound, max(range.lowerBound, start + delta))
  }

  /// "4:50:00" for long timers, "25:00" otherwise.
  static func label(minutes: Int) -> String {
    minutes >= 60
      ? String(format: "%d:%02d:00", minutes / 60, minutes % 60) : String(format: "%d:00", minutes)
  }
}

/// A horizontal ruler: one tick per minute, a label every five, the value under the marker.
struct TimerDial: View {
  @Binding var minutes: Int
  var range: ClosedRange<Int> = 1...FocusTimerModel.maximumMinutes
  var tint: Color = IslandTint.timer
  @State private var dragStart: Int?
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    GeometryReader { proxy in
      let width = proxy.size.width
      Canvas { context, size in
        let center = size.width / 2
        let visible = Int(size.width / TimerDialMath.spacing / 2) + 2
        for offset in -visible...visible {
          let value = minutes + offset
          guard range.contains(value) else { continue }
          let x = center + CGFloat(offset) * TimerDialMath.spacing
          let distance = abs(x - center) / center
          let fade = max(0.08, 1 - distance * 1.1)
          let major = value % 5 == 0
          let height: CGFloat = offset == 0 ? 26 : major ? 20 : 14
          let rect = CGRect(x: x - 1, y: size.height - 8 - height, width: 2, height: height)
          let color = offset == 0 ? Color.white : tint.opacity(fade)
          context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(color))
          if major {
            let label = context.resolve(
              Text("\(value)").font(.system(size: 11, weight: .semibold)).monospacedDigit()
                .foregroundStyle(offset == 0 ? Color.white : tint.opacity(fade)))
            context.draw(label, at: CGPoint(x: x, y: 8))
          }
        }
        var marker = Path()
        marker.move(to: CGPoint(x: center - 4, y: size.height))
        marker.addLine(to: CGPoint(x: center + 4, y: size.height))
        marker.addLine(to: CGPoint(x: center, y: size.height - 6))
        marker.closeSubpath()
        context.fill(marker, with: .color(tint))
      }
      .contentShape(Rectangle())
      .gesture(
        DragGesture(minimumDistance: 1)
          .onChanged { value in
            let start = dragStart ?? minutes
            if dragStart == nil { dragStart = minutes }
            update(TimerDialMath.minutes(from: start, translation: value.translation.width, range: range))
          }
          .onEnded { _ in dragStart = nil }
      )
      .onTapGesture { location in
        // Tapping a tick jumps to it.
        let offset = Int(((location.x - width / 2) / TimerDialMath.spacing).rounded())
        withAnimation(NotchMotion.press(reduceMotion: reduceMotion)) {
          update(min(range.upperBound, max(range.lowerBound, minutes + offset)))
        }
      }
    }
    .frame(height: 48)
    .mask(
      LinearGradient(
        stops: [
          .init(color: .clear, location: 0), .init(color: .black, location: 0.15),
          .init(color: .black, location: 0.85), .init(color: .clear, location: 1),
        ], startPoint: .leading, endPoint: .trailing)
    )
    .accessibilityElement()
    .accessibilityLabel("Timer length")
    .accessibilityValue("\(minutes) minutes")
    .accessibilityAdjustableAction { direction in
      update(min(range.upperBound, max(range.lowerBound, minutes + (direction == .increment ? 1 : -1))))
    }
  }

  private func update(_ value: Int) {
    guard value != minutes else { return }
    minutes = value
    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
  }
}
