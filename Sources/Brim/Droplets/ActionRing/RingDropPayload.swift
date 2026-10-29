import Foundation

/// What a drag in the ring editor carries, encoded as plain text so it works with `Transferable`.
enum RingDropPayload: Equatable {
  /// An existing slot, identified by ring and position.
  case slot(ring: Int, index: Int)
  /// A new action from the palette.
  case action(kind: RingActionKind, argument: String)

  var text: String {
    switch self {
    case .slot(let ring, let index): "slot:\(ring):\(index)"
    case .action(let kind, let argument): "action:\(kind.rawValue):\(argument)"
    }
  }

  init?(_ text: String) {
    let parts = text.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
    switch parts.first {
    case "slot":
      guard parts.count == 3, let ring = Int(parts[1]), let index = Int(parts[2]) else { return nil }
      self = .slot(ring: ring, index: index)
    case "action":
      guard parts.count == 3, let kind = RingActionKind(rawValue: parts[1]) else { return nil }
      self = .action(kind: kind, argument: parts[2])
    default: return nil
    }
  }
}

extension RingLayout {
  /// Applies a drop onto `(ring, index)`: slots swap within a ring and copy across rings,
  /// palette actions fill the slot.
  func applying(_ payload: RingDropPayload, toRing ring: Int, index: Int) -> RingLayout {
    switch payload {
    case .slot(let fromRing, let from):
      return fromRing == ring
        ? swapping(ring: ring, from: from, to: index)
        : copying(fromRing: fromRing, from: from, toRing: ring, to: index)
    case .action(let kind, let argument):
      return setting(RingSlot(kind: kind, argument: argument), ring: ring, index: index)
    }
  }
}
