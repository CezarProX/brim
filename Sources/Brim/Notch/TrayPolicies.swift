import Foundation

/// Where a tray shows up. `notch` keeps files in the island tray only, `floating` only in the
/// pointer-side trays, `both` lets every gesture use its own surface (drop on the notch lands in
/// the notch tray, shaking a drag opens a floating tray).
enum TrayPlacement: String, CaseIterable, Identifiable, Sendable {
  case notch = "Notch", floating = "Floating", both = "Both"
  var id: String { rawValue }
}

/// Pure routing decisions for the tray settings.
enum TrayRouting {
  enum Destination: Equatable { case notchTray, floatingTray }

  /// Where files dropped on the open or closed island go.
  static func islandDrop(_ placement: TrayPlacement) -> Destination {
    placement == .floating ? .floatingTray : .notchTray
  }

  /// Whether the island should switch to the Tray page after a drop.
  static func opensIslandAfterDrop(placement: TrayPlacement, openAfterDrop: Bool) -> Bool {
    openAfterDrop && islandDrop(placement) == .notchTray
  }

  /// Whether shaking a file drag opens a floating tray (the quick action tiles always appear).
  /// Only the Floating placement does: otherwise Drop on the tiles already parks files in the island's Tray.
  static func shakeOpensFloatingTray(_ placement: TrayPlacement) -> Bool { placement == .floating }
}

/// Pinned items float to the front and survive the cap; everything else keeps its order.
enum FileTrayOrdering {
  static func arranged(_ items: [FileTrayItem], limit: Int = 100) -> [FileTrayItem] {
    let pinned = items.filter(\.pinned)
    let rest = items.filter { !$0.pinned }
    return Array((pinned + rest).prefix(limit))
  }
}

/// Decides what happens to a tray item once the user drags it out.
enum DragOutPolicy {
  /// The item leaves the tray only when the setting is on and the drag did not end back on a tray.
  static func shouldRemove(enabled: Bool, releasedOnTray: Bool, pinned: Bool) -> Bool {
    enabled && !releasedOnTray && !pinned
  }
}

/// Mirrors one floating tray's files into the others.
enum TraySync {
  /// The list the other trays should hold, or nil when they already match.
  static func mirror(source: [URL], target: [URL]) -> [URL]? { source == target ? nil : source }
}
