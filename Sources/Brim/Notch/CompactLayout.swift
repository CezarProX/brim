import AppKit
import SwiftUI

/// One set of measurements for everything the closed island shows: flashes, HUD strips, activity
/// rows and notifications.
///
/// - Notch: the left wing holds the glyph and the right wing the label or readout, each centred in
///   its wing, clear of the shape's rounded end on the outside and of the camera housing inside.
///   Wings are as wide as their content needs, and equal, so the camera stays centred.
/// - Pill (no camera): glyph and label form one centred group with balanced insets; the pill is as
///   wide as that group (never narrower than the idle pill).
///
/// Rule for colour: the glyph carries the tint; labels and readouts are white.
enum CompactLayout {
  /// The frame a compact glyph sits in, and the symbol size drawn inside it.
  static let glyphSlot: CGFloat = 24
  static let glyphSize: CGFloat = 16
  /// Labels and readouts: 13pt semibold, scaled down at most to 85% before truncating.
  static let labelSize: CGFloat = 13
  static var labelFont: Font { .system(size: labelSize, weight: .semibold) }
  static let labelMinimumScale: CGFloat = 0.85
  /// Widest label each layout gives room for; longer text scales down, then truncates.
  static let notchLabelLimit: CGFloat = 130
  static let pillLabelLimit: CGFloat = 200
  /// Space between the glyph and the label in a pill group.
  static let groupSpacing: CGFloat = 8
  /// Notch wing insets: from the shape's side edge (past its bottom radius) to the content, and
  /// from the content to the camera housing.
  static let wingOuter: CGFloat = 14
  static let wingInner: CGFloat = 8
  /// Pill insets, chosen so the glyph ink and the label ink sit about the end radius (18pt) from each end.
  static let pillLeading: CGFloat = 16
  static let pillTrailing: CGFloat = 18
  /// Level readouts: the bar beside the percent in a notch wing, and the longer bar on the pill.
  static let notchBarWidth: CGFloat = 36
  static let pillBarWidth: CGFloat = 72
  static let barSpacing: CGFloat = 8

  private static let measuringFont = NSFont.systemFont(ofSize: labelSize, weight: .semibold)

  /// Width a label needs at full size, capped at `limit`.
  static func labelWidth(_ text: String, limit: CGFloat) -> CGFloat {
    let natural = (text as NSString).size(withAttributes: [.font: measuringFont]).width
    return min(limit, ceil(natural) + 2)
  }

  /// The percent slot is sized for "100" so the readout never changes width while a level moves.
  static var percentWidth: CGFloat {
    let font = NSFont.monospacedDigitSystemFont(ofSize: labelSize, weight: .semibold)
    return ceil(("100" as NSString).size(withAttributes: [.font: font]).width) + 2
  }

  /// Width of a flash's readout: the bar and percent for a level, else its (short) title.
  static func readoutWidth(_ flash: IslandFlash, floating: Bool) -> CGFloat {
    if flash.value != nil {
      return (floating ? pillBarWidth : notchBarWidth) + barSpacing + percentWidth
    }
    return labelWidth(flash.compactText, limit: floating ? pillLabelLimit : notchLabelLimit)
  }

  /// One notch wing holding `content` points of glyph or label.
  static func wing(content: CGFloat) -> CGFloat { wingOuter + max(glyphSlot, content) + wingInner }

  /// A pill holding a glyph and `content` points of label beside it (0 = glyph only).
  static func pillWidth(content: CGFloat) -> CGFloat {
    pillLeading + glyphSlot + (content > 0 ? groupSpacing + content : 0) + pillTrailing
  }
}

extension IslandFlash {
  /// What the compact island prints for this flash: the short form when there is one.
  var compactText: String { shortTitle ?? title }
}

/// Notch layout: `leading` centred in the left wing, `trailing` centred in the right wing, nothing
/// in the band the camera housing covers.
struct CompactWingsRow<Leading: View, Trailing: View>: View {
  let leftWing: CGFloat
  let rightWing: CGFloat
  let notchWidth: CGFloat
  /// How far the shape's side edges sit inside this row's frame (its shoulder); 0 when the shape
  /// is already widened by it, as the HUD strip is.
  var shoulder: CGFloat = 0
  @ViewBuilder var leading: Leading
  @ViewBuilder var trailing: Trailing

  var body: some View {
    let outer = CompactLayout.wingOuter + shoulder
    let inner = CompactLayout.wingInner
    // Each wing sits in a ZStack so an empty side (the right one while a second activity shows its
    // bubble) still keeps its width; a frame on an empty view takes no room, and the row would
    // then centre off the camera and slide the left glyph under the housing.
    // Content hugs the outer edge of its wing, so a short glyph opposite a long label (an icon
    // and a sender's name) sits as far in from the left as the label does from the right, instead
    // of floating in the middle of an empty wing.
    HStack(spacing: 0) {
      ZStack(alignment: .leading) { leading }
        .frame(width: max(0, leftWing - outer - inner), alignment: .leading)
        .padding(.leading, outer).padding(.trailing, inner)
      Color.clear.frame(width: notchWidth)
      ZStack(alignment: .trailing) { trailing }
        .frame(width: max(0, rightWing - outer - inner), alignment: .trailing)
        .padding(.leading, inner).padding(.trailing, outer)
    }
    .frame(width: leftWing + notchWidth + rightWing)
  }
}

/// Pill layout: glyph and label as one centred group with balanced insets.
struct CompactGroupRow<Leading: View, Trailing: View>: View {
  @ViewBuilder var leading: Leading
  @ViewBuilder var trailing: Trailing

  var body: some View {
    HStack(spacing: CompactLayout.groupSpacing) {
      // A wide symbol (AirDrop's radio waves) widens its slot rather than spilling toward the end.
      leading.frame(minWidth: CompactLayout.glyphSlot).frame(height: CompactLayout.glyphSlot)
      trailing
    }
    .padding(.leading, CompactLayout.pillLeading).padding(.trailing, CompactLayout.pillTrailing)
    .frame(maxWidth: .infinity)
  }
}
