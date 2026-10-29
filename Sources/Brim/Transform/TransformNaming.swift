import Foundation

/// Output naming: results never overwrite anything, and collisions get " 2", " 3"…
enum TransformNaming {
  static func downloadsFolder(files: FileManager = .default) -> URL {
    files.urls(for: .downloadsDirectory, in: .userDomainMask).first
      ?? files.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
  }

  /// The folder a result for `source` goes in. Falls back to Downloads when the
  /// original's folder isn't writable (a read-only volume, for example).
  static func folder(for source: URL, policy: TransformOutputPolicy, files: FileManager = .default, downloads: URL? = nil) -> URL {
    let downloads = downloads ?? downloadsFolder(files: files)
    switch policy.destination {
    case .downloads: return downloads
    case .nextToOriginal:
      let parent = source.deletingLastPathComponent()
      return files.isWritableFile(atPath: parent.path) ? parent : downloads
    }
  }

  /// "name-compressed.jpg", or "name-compressed 2.jpg" if that exists or is reserved.
  static func outputURL(
    for source: URL, suffix: String, fileExtension: String, in folder: URL,
    reserved: Set<String> = [], files: FileManager = .default
  ) -> URL {
    let base = source.deletingPathExtension().lastPathComponent
    return uniqueURL(in: folder, name: suffix.isEmpty ? base : "\(base)-\(suffix)",
                     fileExtension: fileExtension, reserved: reserved, files: files)
  }

  static func uniqueURL(
    in folder: URL, name: String, fileExtension: String, reserved: Set<String> = [],
    files: FileManager = .default
  ) -> URL {
    func candidate(_ index: Int) -> URL {
      let stem = index == 1 ? name : "\(name) \(index)"
      let url = folder.appendingPathComponent(stem)
      return fileExtension.isEmpty ? url : url.appendingPathExtension(fileExtension)
    }
    var index = 1
    while files.fileExists(atPath: candidate(index).path) || reserved.contains(candidate(index).path) {
      index += 1
    }
    return candidate(index)
  }

  // MARK: Rename pattern

  /// Expands {name}, {n} (1-based, or {n:3} for zero padding) and {date} (yyyy-MM-dd).
  /// Path separators and colons are dropped so a pattern can't escape the folder.
  static func renamed(
    pattern: String, originalName: String, index: Int, date: Date = .now,
    calendar: Calendar = Calendar(identifier: .gregorian)
  ) -> String {
    var result = pattern.isEmpty ? "{name}" : pattern
    let parts = calendar.dateComponents(in: .current, from: date)
    let day = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    result = result.replacingOccurrences(of: "{name}", with: originalName)
    result = result.replacingOccurrences(of: "{date}", with: day)
    if let range = result.range(of: #"\{n:(\d{1,2})\}"#, options: .regularExpression) {
      let digits = Int(result[range].dropFirst(3).dropLast()) ?? 1
      result.replaceSubrange(range, with: String(format: "%0\(digits)d", index))
    }
    result = result.replacingOccurrences(of: "{n}", with: String(index))
    let cleaned = result.replacingOccurrences(of: "/", with: "-")
      .replacingOccurrences(of: ":", with: "-")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let safe = cleaned.drop(while: { $0 == "." })
    return safe.isEmpty ? originalName : String(safe)
  }
}

/// "4.2 MB → 680 KB, −84%"
enum TransformSizeSummary {
  static func bytes(_ value: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
  }

  static func percentChange(before: Int64, after: Int64) -> Int {
    guard before > 0 else { return 0 }
    return Int((Double(after - before) / Double(before) * 100).rounded())
  }

  static func text(before: Int64, after: Int64) -> String {
    let change = percentChange(before: before, after: after)
    let sign = change > 0 ? "+" : change < 0 ? "−" : ""
    return "\(bytes(before)) → \(bytes(after)), \(sign)\(abs(change))%"
  }
}
