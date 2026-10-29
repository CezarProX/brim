import Foundation

/// Up to three rings. Every edit returns a new layout; the caller owns persistence.
struct RingLayout: Codable, Equatable, Sendable {
  static let maxRings = 3
  private(set) var rings: [RingPage]

  init(rings: [RingPage]) {
    let kept = Array(rings.prefix(Self.maxRings))
    self.rings = kept.isEmpty ? [RingPage(name: "Ring 1")] : kept
  }

  /// Eight useful actions, matching the original fixed ring.
  static var standard: RingLayout {
    let slots: [RingSlot?] = [
      RingSlot(kind: .builtIn, argument: RingBuiltIn.capture.rawValue),
      RingSlot(kind: .builtIn, argument: RingBuiltIn.grabText.rawValue),
      RingSlot(kind: .builtIn, argument: RingBuiltIn.colorPicker.rawValue),
      RingSlot(kind: .media, argument: RingMedia.playPause.rawValue),
      RingSlot(kind: .toggle, argument: RingToggle.keepAwake.rawValue),
      RingSlot(kind: .builtIn, argument: RingBuiltIn.voiceMemo.rawValue),
      RingSlot(kind: .builtIn, argument: RingBuiltIn.emojiPicker.rawValue),
      RingSlot(kind: .builtIn, argument: RingBuiltIn.settings.rawValue),
    ]
    return RingLayout(rings: [RingPage(name: "Ring 1", slots: slots)])
  }

  var canAddRing: Bool { rings.count < Self.maxRings }

  func addingRing() -> RingLayout {
    guard canAddRing else { return self }
    return RingLayout(rings: rings + [RingPage(name: "Ring \(rings.count + 1)")])
  }

  func removingRing(at index: Int) -> RingLayout {
    guard rings.count > 1, rings.indices.contains(index) else { return self }
    var next = rings
    next.remove(at: index)
    return RingLayout(rings: next)
  }

  func renamingRing(at index: Int, to name: String) -> RingLayout {
    guard rings.indices.contains(index) else { return self }
    var next = rings
    next[index].name = String(name.prefix(24))
    return RingLayout(rings: next)
  }

  func setting(_ slot: RingSlot?, ring: Int, index: Int) -> RingLayout {
    guard rings.indices.contains(ring), (0..<RingPage.slotCount).contains(index) else { return self }
    var next = rings
    next[ring].slots[index] = slot
    return RingLayout(rings: next)
  }

  /// Drag-and-drop within one ring: the two slots trade places (an empty slot moves too).
  func swapping(ring: Int, from: Int, to: Int) -> RingLayout {
    guard rings.indices.contains(ring), (0..<RingPage.slotCount).contains(from),
      (0..<RingPage.slotCount).contains(to), from != to
    else { return self }
    var next = rings
    next[ring].slots.swapAt(from, to)
    return RingLayout(rings: next)
  }

  /// Drops a copy of a slot from one ring onto a position in another (or the same) ring.
  func copying(fromRing: Int, from: Int, toRing: Int, to: Int) -> RingLayout {
    guard rings.indices.contains(fromRing), (0..<RingPage.slotCount).contains(from),
      let source = rings[fromRing].slots[from]
    else { return self }
    var copy = source
    copy.id = UUID()
    return setting(copy, ring: toRing, index: to)
  }

  /// The configured, non-empty slot count of a ring.
  func filledCount(ring: Int) -> Int {
    rings.indices.contains(ring) ? rings[ring].slots.compactMap { $0 }.count : 0
  }
}

/// How the ring is opened and chosen from.
enum RingTriggerMode: String, CaseIterable, Identifiable, Sendable {
  /// Press the shortcut to open, click a slot to choose.
  case toggle
  /// Hold the shortcut to open, release over a slot to choose it.
  case holdAndRelease
  var id: String { rawValue }
  var title: String {
    switch self {
    case .toggle: "Press to open, click to choose"
    case .holdAndRelease: "Hold to open, release to choose"
    }
  }
}

/// A modifier that opens the ring when held alone (the practical stand-in for a
/// four-finger tap, which needs the private MultitouchSupport framework).
enum RingHoldModifier: String, CaseIterable, Identifiable, Sendable {
  case off, option, control, shift
  var id: String { rawValue }
  var title: String {
    switch self {
    case .off: "Off"
    case .option: "Hold ⌥ Option"
    case .control: "Hold ⌃ Control"
    case .shift: "Hold ⇧ Shift"
    }
  }
}

extension AppSettings {
  var ringLayout: RingLayout {
    get {
      guard let data = defaults.data(forKey: "ringLayoutV1"),
        let layout = try? JSONDecoder().decode(RingLayout.self, from: data)
      else { return .standard }
      return layout
    }
    set {
      if let data = try? JSONEncoder().encode(newValue) { defaults.set(data, forKey: "ringLayoutV1") }
    }
  }

  var ringTriggerMode: RingTriggerMode {
    get { defaults.string(forKey: "ringTriggerMode").flatMap(RingTriggerMode.init(rawValue:)) ?? .toggle }
    set { defaults.set(newValue.rawValue, forKey: "ringTriggerMode") }
  }

  var ringHoldModifier: RingHoldModifier {
    get { defaults.string(forKey: "ringHoldModifier").flatMap(RingHoldModifier.init(rawValue:)) ?? .off }
    set { defaults.set(newValue.rawValue, forKey: "ringHoldModifier") }
  }
}
