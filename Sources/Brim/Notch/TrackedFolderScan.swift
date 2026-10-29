import Foundation

/// Pure rules for the tracked-folders watcher.
enum TrackedFolderScan {
  /// Names that are never worth parking: hidden files and half-written downloads.
  static func isIgnorable(_ name: String) -> Bool {
    if name.hasPrefix(".") || name.hasPrefix("~$") { return true }
    let partial: Set<String> = ["download", "crdownload", "part", "partial", "tmp", "temp", "opdownload"]
    return partial.contains((name as NSString).pathExtension.lowercased())
  }

  /// Files in `current` that were not in `known`, oldest name first for a stable order.
  static func newFiles(current: [URL], known: Set<String>) -> [URL] {
    current.filter { !isIgnorable($0.lastPathComponent) && !known.contains($0.lastPathComponent) }
      .sorted { $0.lastPathComponent < $1.lastPathComponent }
  }

  /// Folders that may be watched: existing directories, each once, never a tray-internal folder.
  static func watchable(_ paths: [String], files: FileManager = .default) -> [String] {
    var seen = Set<String>()
    return paths.filter { path in
      var isDirectory: ObjCBool = false
      return files.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
        && seen.insert(path).inserted
    }
  }
}
