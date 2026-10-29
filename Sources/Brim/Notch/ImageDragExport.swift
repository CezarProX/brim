import AppKit
import UniformTypeIdentifiers

/// Dragging an image out of the island: chat apps (WhatsApp, Telegram, Discord, Slack, web chats)
/// accept files, while editors accept image data, so the drag offers a real PNG file first and the
/// raw PNG second. Exports live in a private temp folder and are removed after an hour.
enum ImageDragExport {
  static let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Brim Drags", isDirectory: true)
  static let lifetime: TimeInterval = 3600

  static func provider(for png: Data, date: Date = .now, in directory: URL = folder) -> NSItemProvider? {
    removeStale(in: directory)
    guard let file = write(png, date: date, in: directory) else { return nil }
    let provider = NSItemProvider(object: file as NSURL)
    provider.registerDataRepresentation(forTypeIdentifier: UTType.png.identifier, visibility: .all) { completion in
      completion(png, nil)
      return nil
    }
    provider.suggestedName = file.deletingPathExtension().lastPathComponent
    return provider
  }

  /// "Image 2026-09-25 at 02.41.13.png", like a Finder-named screenshot; a counter keeps names unique.
  static func write(_ png: Data, date: Date, in directory: URL) -> URL? {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
    let base = "Image \(formatter.string(from: date))"
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      for index in 1...99 {
        let name = index == 1 ? base : "\(base) \(index)"
        let url = directory.appendingPathComponent(name).appendingPathExtension("png")
        guard !FileManager.default.fileExists(atPath: url.path) else { continue }
        try png.write(to: url, options: .withoutOverwriting)
        return url
      }
    } catch {
      NSLog("Brim: couldn't prepare the dragged image: \(error.localizedDescription)")
    }
    return nil
  }

  static func removeStale(in directory: URL, now: Date = .now) {
    let files = (try? FileManager.default.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
    for file in files {
      let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? now
      if now.timeIntervalSince(modified) > lifetime { try? FileManager.default.removeItem(at: file) }
    }
  }
}
