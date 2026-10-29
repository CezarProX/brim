import Foundation

/// One Core Audio process object, as read from `kAudioHardwarePropertyProcessObjectList`.
struct AudioProcessInfo: Equatable, Sendable {
  let objectID: UInt32
  let pid: Int32
  let bundleID: String
  let isRunningOutput: Bool
  let isRunningInput: Bool
}

/// An app as the user sees it: all of its helper processes folded into one row.
struct AudioAppEntry: Identifiable, Equatable, Sendable {
  /// Stable key: the app's bundle id (or "system.sounds").
  let id: String
  let name: String
  let processObjectIDs: [UInt32]
  /// Currently producing output (as opposed to merely holding an audio session open).
  let isPlaying: Bool
  let isSystemSounds: Bool
}

protocol AudioProcessListing: Sendable {
  func processes() -> [AudioProcessInfo]
}

enum AudioProcessGrouping {
  static let systemSoundsID = "system.sounds"

  /// Helper processes report their own bundle ids (`com.google.Chrome.helper.Renderer`,
  /// `com.apple.WebKit.GPU`); fold them back into the app the user knows.
  static func appBundleID(for bundleID: String) -> String {
    let lower = bundleID.lowercased()
    if lower.hasPrefix("com.apple.webkit.") || lower.hasPrefix("com.apple.safari.") { return "com.apple.Safari" }
    let parts = bundleID.split(separator: ".", omittingEmptySubsequences: false)
    if let index = parts.firstIndex(where: { $0.lowercased() == "helper" }), index >= 2 {
      return parts[..<index].joined(separator: ".")
    }
    return bundleID
  }

  static func isSystemSounds(_ bundleID: String) -> Bool {
    let lower = bundleID.lowercased()
    return lower.hasPrefix("com.apple.systemsoundserver") || lower == "com.apple.audio.systemsoundserver"
      || lower.hasPrefix("com.apple.coreaudiod")
  }

  /// Groups processes into app rows. Sorted: playing first, then by name.
  /// - Parameters:
  ///   - showPaused: keep apps whose audio session is open but silent.
  ///   - includeSystemSounds: add one "System Sounds" row for alert/notification audio.
  ///   - alwaysInclude: apps that carry a volume change and must stay reachable while silent.
  ///   - excluding: bundle ids to hide (Brim itself).
  static func entries(
    from processes: [AudioProcessInfo], showPaused: Bool, includeSystemSounds: Bool,
    excluding: Set<String> = [], alwaysInclude: Set<String> = [], name: (String) -> String
  ) -> [AudioAppEntry] {
    var order: [String] = []
    var buckets: [String: [AudioProcessInfo]] = [:]
    // Helpers sometimes differ from their app only in letter case (`...browser.helper` vs `...Browser`).
    let canonical = Dictionary(processes.map { ($0.bundleID.lowercased(), $0.bundleID) }, uniquingKeysWith: { a, b in a.count <= b.count ? a : b })
    for process in processes where !process.bundleID.isEmpty {
      let stripped = appBundleID(for: process.bundleID)
      let key = isSystemSounds(process.bundleID) ? systemSoundsID : (canonical[stripped.lowercased()] ?? stripped)
      guard !excluding.contains(key) else { continue }
      if buckets[key] == nil { order.append(key) }
      buckets[key, default: []].append(process)
    }
    let entries: [AudioAppEntry] = order.compactMap { key in
      let group = buckets[key] ?? []
      let playing = group.contains { $0.isRunningOutput }
      let system = key == systemSoundsID
      guard playing || (showPaused && !system) || alwaysInclude.contains(key) else { return nil }
      if system && !includeSystemSounds { return nil }
      return AudioAppEntry(
        id: key, name: system ? "System Sounds" : name(key),
        processObjectIDs: group.map(\.objectID).sorted(), isPlaying: playing, isSystemSounds: system)
    }
    return entries.sorted {
      if $0.isPlaying != $1.isPlaying { return $0.isPlaying }
      return $0.name.localizedStandardCompare($1.name) == .orderedAscending
    }
  }
}
