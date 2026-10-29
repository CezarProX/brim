import CoreGraphics
import Foundation

/// The rules of the "Hidden Bar" technique, kept free of AppKit so they can be tested.
///
/// Two status items sit side by side: a small chevron toggle on the right and a separator to its
/// left. Menu bar items you drag to the left of the separator are hidden by making the separator
/// so long that macOS pushes everything left of it off the screen.
enum HiddenBarPolicy {
  static let expandedLength: CGFloat = 14
  static let maxCollapsedLength: CGFloat = 10_000

  /// Length of the separator. Collapsed is far wider than any display so every item to its left
  /// leaves the screen; expanded is a thin divider.
  static func separatorLength(collapsed: Bool, widestScreen: CGFloat) -> CGFloat {
    guard collapsed else { return expandedLength }
    return min(maxCollapsedLength, max(2_000, widestScreen * 2 + 400))
  }

  /// Collapsing is only safe when the separator is left of the toggle. If it is right of it, the
  /// huge separator would push the toggle off the screen and there would be no way back.
  static func canCollapse(separatorMinX: CGFloat?, toggleMinX: CGFloat?) -> Bool {
    guard let separatorMinX, let toggleMinX else { return false }
    return separatorMinX < toggleMinX
  }

  /// Whether an expanded bar should fold itself back up.
  static func shouldAutoCollapse(expandedAt: Date?, now: Date, delay: TimeInterval, enabled: Bool) -> Bool {
    guard enabled, let expandedAt else { return false }
    return now.timeIntervalSince(expandedAt) >= delay
  }

  /// The chevron points toward where the hidden items will go (left = they are shown).
  static func toggleSymbol(collapsed: Bool) -> String {
    collapsed ? "chevron.left" : "chevron.right"
  }
}
