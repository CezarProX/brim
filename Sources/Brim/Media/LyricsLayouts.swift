import SwiftUI

/// Geometry of the lyrics column, pure so it can be tested.
enum LyricsColumnMath {
  /// Top of each row when rows stack with `spacing`.
  static func tops(heights: [CGFloat], spacing: CGFloat) -> [CGFloat] {
    var y: CGFloat = 0
    return heights.map { height in
      defer { y += height + spacing }
      return y
    }
  }

  /// Vertical centre of a fractional row `position`, interpolated between neighbouring rows.
  static func focusY(tops: [CGFloat], heights: [CGFloat], position: Double) -> CGFloat {
    guard !tops.isEmpty, tops.count == heights.count else { return 0 }
    let clamped = min(Double(tops.count - 1), max(0, position.isFinite ? position : 0))
    let lower = Int(clamped.rounded(.down))
    let upper = min(tops.count - 1, lower + 1)
    let centre = { (row: Int) in tops[row] + heights[row] / 2 }
    return centre(lower) + (centre(upper) - centre(lower)) * CGFloat(clamped - Double(lower))
  }

  /// The position row `row` follows while a step is in flight: the rows from the new line down
  /// trail by `step` each (capped), so the column ripples into place like Apple Music's.
  static func lagged(position: Double, row: Int, step: Double) -> Double {
    guard position.isFinite, step > 0 else { return position }
    let base = position.rounded(.down)
    let phase = position - base
    let behind = Double(min(5, row - Int(base) - 1))
    guard behind > 0, phase > 0 else { return position }
    let delay = behind * step
    return base + min(1, max(0, (phase - delay) / (1 - delay)))
  }
}

/// Stacks lyric rows and slides them so the fractional `position` sits at `anchor` of the height.
/// `position` is animatable, so a line change is one continuous spring instead of a scroll jump.
struct LyricsColumnLayout: Layout {
  var position: Double
  var spacing: CGFloat
  var anchor: CGFloat = 0.45
  /// Cascade per row below the new line; 0 moves the column rigidly.
  var cascade: Double = 0.07

  var animatableData: Double {
    get { position }
    set { position = newValue }
  }

  struct Cache {
    var width: CGFloat = -1
    var heights: [CGFloat] = []
  }

  func makeCache(subviews: Subviews) -> Cache { Cache() }

  /// Rows keep their height while the song plays, so measuring once per width is enough;
  /// the view re-identifies the column when the song changes.
  func updateCache(_ cache: inout Cache, subviews: Subviews) {
    if cache.heights.count != subviews.count { cache = Cache() }
  }

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
    proposal.replacingUnspecifiedDimensions()
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
    if cache.width != bounds.width || cache.heights.count != subviews.count {
      let rowProposal = ProposedViewSize(width: bounds.width, height: nil)
      cache.heights = subviews.map { $0.sizeThatFits(rowProposal).height }
      cache.width = bounds.width
    }
    let heights = cache.heights
    let tops = LyricsColumnMath.tops(heights: heights, spacing: spacing)
    let target = bounds.minY + bounds.height * anchor
    for (row, subview) in subviews.enumerated() {
      let follows = LyricsColumnMath.lagged(position: position, row: row, step: cascade)
      let y = target - LyricsColumnMath.focusY(tops: tops, heights: heights, position: follows) + tops[row]
      subview.place(at: CGPoint(x: bounds.minX, y: y), anchor: .topLeading,
                    proposal: ProposedViewSize(width: bounds.width, height: heights[row]))
    }
  }
}

/// Words laid out like a paragraph, each line centred. Every lyric row uses it, sung or not,
/// so a row is the same height when it becomes active and the column never jumps.
struct LyricWordFlow: Layout {
  var spacing: CGFloat
  var lineSpacing: CGFloat = 2

  private struct Line { var range: Range<Int>; var width: CGFloat; var height: CGFloat }

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let lines = arrange(width: proposal.width ?? .infinity, subviews: subviews)
    let height = lines.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(0, lines.count - 1))
    return CGSize(width: proposal.width ?? lines.map(\.width).max() ?? 0, height: height)
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    var y = bounds.minY
    for line in arrange(width: bounds.width, subviews: subviews) {
      var x = bounds.midX - line.width / 2
      for index in line.range {
        let size = subviews[index].sizeThatFits(.unspecified)
        subviews[index].place(at: CGPoint(x: x, y: y + (line.height - size.height) / 2), proposal: .unspecified)
        x += size.width + spacing
      }
      y += line.height + lineSpacing
    }
  }

  private func arrange(width: CGFloat, subviews: Subviews) -> [Line] {
    var lines: [Line] = []
    var current = Line(range: 0..<0, width: 0, height: 0)
    for (index, subview) in subviews.enumerated() {
      let size = subview.sizeThatFits(.unspecified)
      let added = current.range.isEmpty ? size.width : current.width + spacing + size.width
      if added > width, !current.range.isEmpty {
        lines.append(current)
        current = Line(range: index..<index + 1, width: size.width, height: size.height)
      } else {
        current = Line(range: current.range.lowerBound..<index + 1, width: added, height: max(current.height, size.height))
      }
    }
    if !current.range.isEmpty { lines.append(current) }
    return lines
  }
}
