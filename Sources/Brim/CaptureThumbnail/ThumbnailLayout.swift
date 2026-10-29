import CoreGraphics
import Foundation

/// Where floating capture thumbnails go: one column per screen, newest card nearest the corner.
/// Pure geometry in AppKit screen coordinates (origin bottom-left, y up), so it is testable.
enum ThumbnailLayout {
  static let cardSize = CGSize(width: 280, height: 230)
  static let cornerRadius: CGFloat = 22
  /// Gap between a card and the screen's visible edges.
  static let margin: CGFloat = 18
  static let spacing: CGFloat = 12
  /// Transparent room around a card inside its panel for the shadow and the slide-in.
  static let shadowInset: CGFloat = 28
  static let maxVisible = 4

  /// How many cards fit in one column on a screen, capped at `maxVisible` and never below 1.
  static func capacity(in bounds: CGRect) -> Int {
    let fitting = Int(((bounds.height - 2 * margin + spacing) / (cardSize.height + spacing)).rounded(.down))
    return max(1, min(maxVisible, fitting))
  }

  /// The card in `slot` (0 = newest, in the corner) inside a screen's visible frame.
  static func cardFrame(slot: Int, corner: ThumbnailCorner, in bounds: CGRect) -> CGRect {
    let x = corner.isRight ? bounds.maxX - margin - cardSize.width : bounds.minX + margin
    let step = CGFloat(max(0, slot)) * (cardSize.height + spacing)
    let y = corner.isBottom ? bounds.minY + margin + step : bounds.maxY - margin - cardSize.height - step
    return CGRect(origin: CGPoint(x: x, y: y), size: cardSize)
  }

  /// The panel around a card: the card plus room for its shadow. It reaches past the screen edge,
  /// so a card sliding in or swiped away is never cut off short of the edge.
  static func panelFrame(forCard card: CGRect) -> CGRect {
    card.insetBy(dx: -shadowInset, dy: -shadowInset)
  }

  /// Horizontal offset that puts a card fully past the nearest screen edge.
  static func offscreenOffset(for corner: ThumbnailCorner) -> CGFloat {
    (cardSize.width + margin + shadowInset) * corner.outward
  }

  /// Slots for cards listed oldest first: the newest gets slot 0.
  static func slots<ID: Hashable>(oldestFirst ids: [ID]) -> [ID: Int] {
    Dictionary(uniqueKeysWithValues: ids.reversed().enumerated().map { ($0.element, $0.offset) })
  }

  /// Which cards to close so at most `capacity` remain: oldest unpinned first, then oldest pinned.
  static func evictions<ID: Hashable>(oldestFirst ids: [ID], pinned: Set<ID>, capacity: Int) -> [ID] {
    let excess = ids.count - max(1, capacity)
    guard excess > 0 else { return [] }
    let ordered = ids.filter { !pinned.contains($0) } + ids.filter { pinned.contains($0) }
    return Array(ordered.prefix(excess))
  }
}
