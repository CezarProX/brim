import SwiftUI

/// The thin level track used by every level HUD: a dim capsule with a tinted fill.
struct HUDLevelBar: View {
  let value: Double
  let tint: Color
  var width: CGFloat = 36
  var height: CGFloat = 5
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    Capsule().fill(.white.opacity(0.2))
      .overlay(alignment: .leading) {
        Capsule().fill(tint)
          .frame(width: max(height, width * CGFloat(HUDLevelMath.clamp(value))))
          .opacity(value <= 0 ? 0 : 1)
      }
      .frame(width: width, height: height)
      .animation(reduceMotion ? nil : .spring(duration: 0.22, bounce: 0), value: value)
      .accessibilityElement()
      .accessibilityValue("\(HUDLevelMath.percent(value)) percent")
  }
}
