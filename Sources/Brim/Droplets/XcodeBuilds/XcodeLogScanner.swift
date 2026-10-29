import Foundation

/// Reads DerivedData for build activity. Cheap: it lists directories and file dates, and only
/// parses the manifest of the one project that was written to most recently.
enum XcodeLogScanner {
  static var derivedData: URL {
    FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Developer/Xcode/DerivedData")
  }

  static func snapshot(root: URL = derivedData, xcodebuildRunning: Bool) -> XcodeLogSnapshot? {
    let files = FileManager.default
    guard let projects = try? files.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return nil }
    var best: (project: String, log: URL, modified: Date, folder: URL)?
    for project in projects {
      let folder = project.appendingPathComponent("Logs/Build")
      guard let logs = try? files.contentsOfDirectory(
        at: folder, includingPropertiesForKeys: [.contentModificationDateKey], options: .skipsHiddenFiles)
      else { continue }
      for log in logs where log.pathExtension == "xcactivitylog" {
        guard let modified = try? log.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        else { continue }
        if best == nil || modified > best!.modified {
          best = (XcodeBuildDetector.projectName(fromDerivedDataFolder: project.lastPathComponent), log, modified, folder)
        }
      }
    }
    guard let best else { return nil }
    let manifest = (try? Data(contentsOf: best.folder.appendingPathComponent("LogStoreManifest.plist"))).map(XcodeBuildDetector.parseManifest) ?? []
    return XcodeLogSnapshot(
      project: best.project, latestLog: best.log.lastPathComponent, latestLogModified: best.modified,
      entries: manifest, xcodebuildRunning: xcodebuildRunning)
  }

  /// Whether a command-line `xcodebuild` is running (Xcode's own builds are caught by log activity).
  static func isXcodebuildRunning() async -> Bool {
    guard let result = await DropletProcess.run("/usr/bin/pgrep", ["-x", "xcodebuild"], timeout: 3) else { return false }
    return result.status == 0
  }
}
