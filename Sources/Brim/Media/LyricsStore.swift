import CryptoKit
import Foundation

/// A bounded on-disk cache of fetched lyrics (including "none found", so a song without
/// lyrics is not asked about again every play).
struct LyricsStore: Sendable {
  struct Entry: Codable, Equatable {
    let synced: String?
    let fetchedAt: Date
  }

  static let maxEntries = 300
  static let missLifetime: TimeInterval = 7 * 24 * 3600
  let directory: URL

  static var standard: LyricsStore {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? FileManager.default.temporaryDirectory
    return LyricsStore(directory: base.appendingPathComponent("Brim/Lyrics", isDirectory: true))
  }

  static func key(title: String, artist: String, album: String, duration: TimeInterval) -> String {
    // "v2": lookups before it remembered a busy server as "no lyrics"; those entries are ignored.
    // "v3": word-timed AMLL lyrics are tried first, so songs cached with line timing look again.
    let raw = "v3\u{1F}" + [title, artist, album].map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
      .joined(separator: "\u{1F}") + "\u{1F}\(Int(duration.rounded()))"
    return SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
  }

  func load(key: String, now: Date = .now) -> Entry? {
    guard let data = try? Data(contentsOf: file(key)),
      let entry = try? JSONDecoder().decode(Entry.self, from: data)
    else { return nil }
    if entry.synced == nil, now.timeIntervalSince(entry.fetchedAt) > Self.missLifetime { return nil }
    return entry
  }

  func save(_ entry: Entry, key: String) {
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      try JSONEncoder().encode(entry).write(to: file(key), options: .atomic)
      prune()
    } catch {
      // A cache that cannot be written only costs a refetch.
    }
  }

  /// Drops the oldest files beyond `maxEntries`.
  func prune(limit: Int = LyricsStore.maxEntries) {
    let keys: [URLResourceKey] = [.contentModificationDateKey]
    guard let files = try? FileManager.default.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: keys), files.count > limit
    else { return }
    let sorted = files.sorted {
      let a = (try? $0.resourceValues(forKeys: Set(keys)).contentModificationDate) ?? .distantPast
      let b = (try? $1.resourceValues(forKeys: Set(keys)).contentModificationDate) ?? .distantPast
      return a < b
    }
    for url in sorted.prefix(files.count - limit) { try? FileManager.default.removeItem(at: url) }
  }

  func clear() { try? FileManager.default.removeItem(at: directory) }

  private func file(_ key: String) -> URL { directory.appendingPathComponent("\(key).json") }
}
