import Foundation

/// Which side of the island a detached bubble hangs on.
enum IslandBubbleSide: Equatable, CaseIterable {
  case leading, trailing
}

/// The detached bubbles beside the island, like iPhone's split Dynamic Island: at most one per side.
struct IslandBubblePair: Equatable {
  var leading: IslandActivity?
  var trailing: IslandActivity?

  static let none = IslandBubblePair()

  var isEmpty: Bool { leading == nil && trailing == nil }
  var count: Int { (leading == nil ? 0 : 1) + (trailing == nil ? 0 : 1) }

  func activity(on side: IslandBubbleSide) -> IslandActivity? {
    side == .leading ? leading : trailing
  }

  /// Places up to two companions, like iPhone's split island:
  /// - One bubble always hangs on the right.
  /// - Two: the second-ranked activity on the right, the third on the left.
  /// - Bubbles already showing keep their side (`previous`), so one never jumps across the island
  ///   when another arrives: the newcomer takes the free side.
  static func placing(_ companions: [IslandActivity], after previous: IslandBubblePair = .none) -> IslandBubblePair {
    let shown = Array(companions.prefix(2))
    guard shown.count == 2 else { return IslandBubblePair(trailing: shown.first) }
    let (best, next) = (shown[0], shown[1])
    if let right = previous.trailing, shown.contains(right) {
      return IslandBubblePair(leading: right == best ? next : best, trailing: right)
    }
    if let left = previous.leading, shown.contains(left) {
      return IslandBubblePair(leading: left, trailing: left == best ? next : best)
    }
    return IslandBubblePair(leading: next, trailing: best)
  }
}

extension IslandActivities {
  /// The live activities that ride in bubbles beside `activity` (the one on the island), best
  /// first: a playing song always gets one, then the next ranked live activity. Ambient app skins
  /// never take a bubble. At most two, one per side.
  func companions(to activity: IslandActivity?) -> [IslandActivity] {
    var result: [IslandActivity] = music && activity != .music ? [.music] : []
    for candidate in available where result.count < 2 {
      guard candidate != activity, !Self.ambient.contains(candidate), !result.contains(candidate) else { continue }
      result.append(candidate)
    }
    return result
  }

  /// The second-ranked live activity after the primary: the 2nd bubble when two show.
  var tertiary: IslandActivity? { companions(to: primary).dropFirst().first }

  /// Both bubbles beside `activity`, placed fresh (no bubble showing before).
  func bubbles(beside activity: IslandActivity?, after previous: IslandBubblePair = .none) -> IslandBubblePair {
    .placing(companions(to: activity), after: previous)
  }
}
