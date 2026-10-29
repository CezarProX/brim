import SwiftUI

/// "Progressive blur": a frosted halo around the open island that fades out into the desktop, so the
/// shell sits in a soft pool of blur instead of a hard edge. It is drawn behind the shell, never
/// takes hits, and is off in low-battery mode.
struct ProgressiveBlurHalo: View {
  /// The visible shell the halo surrounds.
  let size: CGSize
  var floating = false
  static let reach: CGFloat = 34

  var body: some View {
    let reach = Self.reach
    IslandBackdropBlur(liquid: false, tinted: false, clarity: 0.55)
      .frame(width: size.width + 2 * reach, height: size.height + reach)
      .mask(alignment: .top) {
        RoundedRectangle(cornerRadius: floating ? 44 : 48, style: .continuous)
          .fill(.black)
          .frame(width: size.width + reach, height: size.height + reach * 0.5)
          .blur(radius: reach * 0.55)
          .frame(width: size.width + 2 * reach, height: size.height + reach, alignment: .top)
      }
      .opacity(0.9)
      .allowsHitTesting(false)
      .accessibilityHidden(true)
  }
}
