import Foundation

/// Sizes and trashing. Sizes are allocated bytes on disk; symlinks are counted, never followed.
enum CleanerScanner {
  static func size(of url: URL, fileManager: FileManager = .default) -> Int64 {
    let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isSymbolicLinkKey, .isDirectoryKey]
    guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return 0 }
    if values.isSymbolicLink == true || values.isDirectory != true {
      return Int64(values.totalFileAllocatedSize ?? 0)
    }
    var total: Int64 = 0
    let enumerator = fileManager.enumerator(
      at: url, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true })
    while let item = enumerator?.nextObject() as? URL {
      guard let v = try? item.resourceValues(forKeys: Set(keys)) else { continue }
      total += Int64(v.totalFileAllocatedSize ?? 0)
    }
    return total
  }

  struct TrashOutcome: Sendable {
    var moved: [URL] = []
    var failed: [(URL, String)] = []
    var freed: Int64 = 0
  }

  /// Moves each item to the Trash (never deletes). Items that fail the safety predicate are
  /// reported as failures instead of being touched.
  static func trash(
    _ urls: [URL], sizes: [URL: Int64] = [:],
    trasher: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) },
    allow: (URL) -> Bool
  ) -> TrashOutcome {
    var outcome = TrashOutcome()
    for url in urls {
      guard allow(url) else {
        outcome.failed.append((url, "Not allowed: outside the places Cleaner may touch"))
        continue
      }
      do {
        try trasher(url)
        outcome.moved.append(url)
        outcome.freed += sizes[url] ?? 0
      } catch {
        outcome.failed.append((url, error.localizedDescription))
      }
    }
    return outcome
  }

  static func format(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    formatter.allowsNonnumericFormatting = false
    return formatter.string(fromByteCount: bytes)
  }
}
