import Foundation

/// Brim was called QuickShot during development. Installs from that time keep their data: on launch,
/// the old Application Support and Logs folders move into Brim's, and the old preferences are copied
/// into Brim's own domain. Each step only fills in what Brim does not have yet, so it is safe to run
/// on every launch and never overwrites anything.
enum LegacyMigration {
  private static let legacyName = "QuickShot"
  private static let legacyBundleID = "com.cezar.quickshot"
  private static let doneKey = "legacyMigrationDone"

  static func run(defaults: UserDefaults = .standard) {
    let files = FileManager.default
    let library = files.urls(for: .libraryDirectory, in: .userDomainMask)[0]
    for folder in ["Application Support", "Logs"] {
      let base = library.appendingPathComponent(folder, isDirectory: true)
      mergeFolder(
        from: base.appendingPathComponent(legacyName, isDirectory: true),
        into: base.appendingPathComponent("Brim", isDirectory: true))
    }
    guard !defaults.bool(forKey: doneKey) else { return }
    if let old = defaults.persistentDomain(forName: legacyBundleID) {
      mergePreferences(old, into: defaults, domain: Bundle.main.bundleIdentifier ?? "io.github.cezarprox.brim")
    }
    defaults.set(true, forKey: doneKey)
  }

  /// Moves each item of `old` into `new` unless `new` already has one by that name (folders on both
  /// sides are merged), then removes `old` if it ended up empty. Items that cannot move stay put.
  static func mergeFolder(from old: URL, into new: URL, files: FileManager = .default) {
    guard let items = try? files.contentsOfDirectory(at: old, includingPropertiesForKeys: nil) else { return }
    do {
      try files.createDirectory(at: new, withIntermediateDirectories: true)
    } catch {
      NSLog("Brim: couldn't create \(new.path) to move old data into: \(error.localizedDescription)")
      return
    }
    for item in items {
      let target = new.appendingPathComponent(item.lastPathComponent)
      var isFolder: ObjCBool = false
      if files.fileExists(atPath: target.path, isDirectory: &isFolder) {
        // Both sides have this folder: merge what is inside it instead of skipping it whole.
        if isFolder.boolValue, (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
          mergeFolder(from: item, into: target, files: files)
        }
        continue
      }
      do {
        try files.moveItem(at: item, to: target)
      } catch {
        NSLog("Brim: couldn't move \(item.lastPathComponent) from old data: \(error.localizedDescription)")
      }
    }
    if (try? files.contentsOfDirectory(atPath: old.path))?.isEmpty == true { try? files.removeItem(at: old) }
  }

  /// Copies `old` preferences into `defaults` for every key its own `domain` does not have yet
  /// (system-wide values such as the language list do not count as set).
  static func mergePreferences(_ old: [String: Any], into defaults: UserDefaults, domain: String) {
    let existing = defaults.persistentDomain(forName: domain) ?? [:]
    for (key, value) in old where existing[key] == nil {
      defaults.set(value, forKey: key)
    }
  }
}
