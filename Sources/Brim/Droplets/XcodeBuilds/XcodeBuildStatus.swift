import Foundation

/// What the island shows for Xcode: nothing, a build in progress, or how the last one ended.
enum XcodeBuildStatus: Equatable, Sendable {
  case idle
  case building(project: String, since: Date)
  case succeeded(project: String, duration: TimeInterval?, warnings: Int)
  case failed(project: String, duration: TimeInterval?, errors: Int)

  var project: String? {
    switch self {
    case .idle: nil
    case .building(let name, _), .succeeded(let name, _, _), .failed(let name, _, _): name
    }
  }
  var isBuilding: Bool { if case .building = self { true } else { false } }
}

/// One finished-or-running build as recorded in DerivedData's `LogStoreManifest.plist`.
struct XcodeManifestEntry: Equatable, Sendable {
  let fileName: String
  let title: String
  let started: Date?
  let stopped: Date?
  /// "S" success, "E" error, "W" warnings, as Xcode writes it.
  let status: String?
  let errors: Int
  let warnings: Int

  var isBuild: Bool { title.hasPrefix("Build") || title.hasPrefix("Archive") }
  var duration: TimeInterval? {
    guard let started, let stopped else { return nil }
    return max(0, stopped.timeIntervalSince(started))
  }
}

/// How the newest finished build ended. Unlike `XcodeBuildStatus`, it does not expire.
struct XcodeLastBuild: Equatable, Sendable {
  let project: String
  let succeeded: Bool
  let errors: Int
  let warnings: Int
  let duration: TimeInterval?
  let finished: Date?
}

/// A point-in-time reading of DerivedData and running processes.
struct XcodeLogSnapshot: Equatable, Sendable {
  var project: String
  /// Name of the newest `.xcactivitylog` and when it last changed.
  var latestLog: String?
  var latestLogModified: Date?
  var entries: [XcodeManifestEntry]
  var xcodebuildRunning: Bool
}

enum XcodeBuildDetector {
  /// A log written to this recently means a build is still running.
  static let activeWindow: TimeInterval = 4
  /// A finished build stays visible this long.
  static let resultWindow: TimeInterval = 8

  static func status(_ snapshot: XcodeLogSnapshot, previous: XcodeBuildStatus, now: Date) -> XcodeBuildStatus {
    let entry = snapshot.entries.first { $0.fileName == snapshot.latestLog }
      ?? snapshot.entries.filter(\.isBuild).max { ($0.started ?? .distantPast) < ($1.started ?? .distantPast) }
    let logIsFresh = snapshot.latestLogModified.map { now.timeIntervalSince($0) < activeWindow } ?? false
    // The manifest says the build ended at or after the last write: not running any more.
    let manifestSaysDone = entry?.stopped.map { stop in
      snapshot.latestLogModified.map { stop >= $0.addingTimeInterval(-1.5) } ?? true
    } ?? false
    let running = snapshot.xcodebuildRunning || (logIsFresh && !manifestSaysDone)
    if running {
      if case .building(let name, _) = previous, name == snapshot.project { return previous }
      return .building(project: snapshot.project, since: entry?.started.flatMap { now.timeIntervalSince($0) < 3600 ? $0 : nil } ?? now)
    }
    if case .building = previous { return finished(entry, snapshot.project, now: now) ?? .idle }
    return recentResult(previous, entry: entry, project: snapshot.project, now: now)
  }

  /// Keeps a result on screen until its window passes, and never resurrects an old one.
  private static func recentResult(_ previous: XcodeBuildStatus, entry: XcodeManifestEntry?, project: String, now: Date) -> XcodeBuildStatus {
    switch previous {
    case .succeeded, .failed:
      let stopped = entry?.stopped ?? .distantPast
      // previous results expire based on when the model first showed them, handled by `expire`.
      return stopped > now.addingTimeInterval(-resultWindow) ? previous : .idle
    default: return .idle
    }
  }

  static func finished(_ entry: XcodeManifestEntry?, _ project: String, now: Date) -> XcodeBuildStatus? {
    guard let entry, entry.isBuild else { return nil }
    if entry.status == "E" || entry.errors > 0 {
      return .failed(project: project, duration: entry.duration, errors: max(1, entry.errors))
    }
    return .succeeded(project: project, duration: entry.duration, warnings: entry.warnings)
  }

  /// The newest build that has ended, from the project written to most recently.
  static func lastBuild(_ snapshot: XcodeLogSnapshot) -> XcodeLastBuild? {
    guard let entry = snapshot.entries.filter({ $0.isBuild && $0.stopped != nil })
      .max(by: { ($0.stopped ?? .distantPast) < ($1.stopped ?? .distantPast) })
    else { return nil }
    let failed = entry.status == "E" || entry.errors > 0
    return XcodeLastBuild(
      project: snapshot.project, succeeded: !failed, errors: entry.errors, warnings: entry.warnings,
      duration: entry.duration, finished: entry.stopped)
  }

  /// "Foo-abcdefghijklmnopqrstuvwxyzabc" (DerivedData folder) to "Foo".
  static func projectName(fromDerivedDataFolder folder: String) -> String {
    guard let dash = folder.lastIndex(of: "-") else { return folder }
    let suffix = folder[folder.index(after: dash)...]
    return suffix.count >= 20 && suffix.allSatisfy({ $0.isLowercase && $0.isLetter }) ? String(folder[..<dash]) : folder
  }

  /// Parses `LogStoreManifest.plist` data. Unknown shapes yield no entries rather than an error.
  static func parseManifest(_ data: Data) -> [XcodeManifestEntry] {
    guard let root = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
      let logs = root["logs"] as? [String: [String: Any]]
    else { return [] }
    return logs.values.map { log in
      let observable = log["primaryObservable"] as? [String: Any] ?? [:]
      func date(_ key: String) -> Date? {
        (log[key] as? Double).map(Date.init(timeIntervalSinceReferenceDate:))
      }
      func count(_ keys: [String]) -> Int {
        for key in keys { if let value = (observable[key] ?? log[key]) as? Int { return value } }
        return 0
      }
      return XcodeManifestEntry(
        fileName: log["fileName"] as? String ?? "",
        title: log["title"] as? String ?? log["signature"] as? String ?? "",
        started: date("timeStartedRecording"), stopped: date("timeStoppedRecording"),
        status: (observable["highLevelStatus"] ?? log["highLevelStatus"]) as? String,
        errors: count(["totalNumberOfErrors", "numberOfErrors"]),
        warnings: count(["totalNumberOfWarnings", "numberOfWarnings"]))
    }
  }

  /// "12s", "1m 05s".
  static func clock(_ seconds: TimeInterval) -> String {
    let total = max(0, Int(seconds.rounded()))
    return total < 60 ? "\(total)s" : "\(total / 60)m \(String(format: "%02d", total % 60))s"
  }
}
