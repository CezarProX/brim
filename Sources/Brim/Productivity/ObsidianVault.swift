import Foundation

struct ObsidianFile: Identifiable, Equatable {
  let url: URL
  let relativePath: String
  let modified: Date
  var id: String { relativePath }
  var title: String { url.deletingPathExtension().lastPathComponent }
}

enum ObsidianError: Error, Equatable { case outsideVault, tooLarge, notMarkdown }

/// A folder of Markdown files opened as an Obsidian vault. Plain file access, no Obsidian needed.
struct ObsidianVault {
  static let maxFiles = 500
  static let maxBytes = 2_000_000
  let root: URL

  init(root: URL) { self.root = root.standardizedFileURL.resolvingSymlinksInPath() }

  var name: String { root.lastPathComponent }

  /// Markdown files, newest first, skipping hidden folders such as `.obsidian` and `.trash`.
  func list(fileManager: FileManager = .default) -> [ObsidianFile] {
    guard let walker = fileManager.enumerator(
      at: root, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
      options: [.skipsHiddenFiles, .skipsPackageDescendants])
    else { return [] }
    var files: [ObsidianFile] = []
    for case let url as URL in walker {
      guard url.pathExtension.lowercased() == "md",
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
        values.isRegularFile == true
      else { continue }
      let full = url.resolvingSymlinksInPath().path
      guard full.hasPrefix(root.path + "/") else { continue }
      files.append(ObsidianFile(
        url: url, relativePath: String(full.dropFirst(root.path.count + 1)),
        modified: values.contentModificationDate ?? .distantPast))
      if files.count >= Self.maxFiles * 4 { break }
    }
    return Array(files.sorted { $0.modified > $1.modified }.prefix(Self.maxFiles))
  }

  /// Resolves a vault-relative path, refusing anything that escapes the vault.
  func resolve(_ relativePath: String) throws -> URL {
    guard relativePath.lowercased().hasSuffix(".md") else { throw ObsidianError.notMarkdown }
    let url = root.appendingPathComponent(relativePath).standardizedFileURL
    guard url.path.hasPrefix(root.path + "/") else { throw ObsidianError.outsideVault }
    // A symlinked file could point anywhere; check where it really lands.
    let real = url.resolvingSymlinksInPath()
    guard real.path.hasPrefix(root.path + "/") else { throw ObsidianError.outsideVault }
    return url
  }

  func read(_ relativePath: String) throws -> String {
    let url = try resolve(relativePath)
    let data = try Data(contentsOf: url)
    guard data.count <= Self.maxBytes else { throw ObsidianError.tooLarge }
    return String(decoding: data, as: UTF8.self)
  }

  func write(_ text: String, to relativePath: String) throws {
    let url = try resolve(relativePath)
    guard text.utf8.count <= Self.maxBytes else { throw ObsidianError.tooLarge }
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: url, options: .atomic)
  }

  /// A vault-relative path for a new note called `name`, numbered when that name is taken.
  func uniqueNotePath(named name: String) -> String {
    var path = name + ".md"
    var number = 2
    while FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path) {
      path = "\(name) \(number).md"
      number += 1
    }
    return path
  }

  // MARK: Daily note

  /// Folder and date format from `.obsidian/daily-notes.json`, with Obsidian's defaults.
  func dailyNoteSettings() -> (folder: String, format: String) {
    let url = root.appendingPathComponent(".obsidian/daily-notes.json")
    guard let data = try? Data(contentsOf: url), data.count < 100_000,
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return ("", "YYYY-MM-DD") }
    let folder = (json["folder"] as? String ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
    let format = (json["format"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "YYYY-MM-DD"
    return (folder, format)
  }

  /// Vault-relative path of the daily note for a date.
  func dailyNotePath(for date: Date, calendar: Calendar = .current) -> String {
    let settings = dailyNoteSettings()
    let name = Self.format(date, moment: settings.format, calendar: calendar)
      .replacingOccurrences(of: "..", with: "")
    return (settings.folder.isEmpty ? "" : settings.folder + "/") + name + ".md"
  }

  /// Creates today's note if it doesn't exist yet and returns its path.
  @discardableResult
  func openDailyNote(for date: Date = .now, calendar: Calendar = .current) throws -> String {
    let path = dailyNotePath(for: date, calendar: calendar)
    let url = try resolve(path)
    if !FileManager.default.fileExists(atPath: url.path) { try write("", to: path) }
    return path
  }

  /// Converts the common Moment.js tokens Obsidian uses (YYYY MM DD dddd MMMM ...) to a string.
  static func format(_ date: Date, moment: String, calendar: Calendar) -> String {
    let swapped = moment
      .replacingOccurrences(of: "YYYY", with: "yyyy").replacingOccurrences(of: "YY", with: "yy")
      .replacingOccurrences(of: "DD", with: "dd").replacingOccurrences(of: "dddd", with: "EEEE")
    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.dateFormat = swapped
    return formatter.string(from: date).replacingOccurrences(of: "/", with: "-")
  }
}
