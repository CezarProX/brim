import Foundation

extension AppSettings {
  private enum IslandTourKey {
    static let completed = "islandTourCompleted"
  }

  /// The Island Tour ran to the end or was skipped; it no longer starts by itself.
  var islandTourCompleted: Bool {
    get { defaults.bool(forKey: IslandTourKey.completed) }
    set { defaults.set(newValue, forKey: IslandTourKey.completed) }
  }
}
