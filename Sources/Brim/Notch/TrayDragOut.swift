import AppKit

/// Drag-out support for the trays: an optional protective copy, and release tracking so a tray can
/// forget an item once it has been dragged away. SwiftUI's `onDrag` has no end callback, so the
/// release is found by polling the mouse button, which works while a drag session owns the events.
@MainActor
enum TrayDragOut {
  private static let folderName = "Brim-TrayDrag"

  /// A provider for the file. With `protect` it is a copy in a scratch folder (a cheap clone on APFS),
  /// so a Finder move on the same volume can never take the original.
  static func provider(for url: URL, protect: Bool) -> NSItemProvider {
    let source = protect ? (protectedCopy(of: url) ?? url) : url
    return NSItemProvider(contentsOf: source) ?? NSItemProvider()
  }

  static func protectedCopy(of url: URL, files: FileManager = .default) -> URL? {
    let root = files.temporaryDirectory.appendingPathComponent(folderName, isDirectory: true)
    let folder = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let target = folder.appendingPathComponent(url.lastPathComponent)
    do {
      try files.createDirectory(at: folder, withIntermediateDirectories: true)
      try files.copyItem(at: url, to: target)
      removeStale(in: root, files: files)
      return target
    } catch { return nil }
  }

  /// Deletes drag copies older than an hour.
  static func removeStale(in root: URL, now: Date = .now, files: FileManager = .default) {
    let keys: [URLResourceKey] = [.creationDateKey]
    guard let entries = try? files.contentsOfDirectory(at: root, includingPropertiesForKeys: keys) else { return }
    for entry in entries {
      let created = (try? entry.resourceValues(forKeys: Set(keys)).creationDate) ?? .distantPast
      if now.timeIntervalSince(created) > 3_600 { try? files.removeItem(at: entry) }
    }
  }

  /// Calls back with the pointer position once the left button comes up (gives up after a minute).
  static func trackRelease(_ completion: @escaping @MainActor (CGPoint) -> Void) {
    Task { @MainActor in
      let deadline = Date().addingTimeInterval(60)
      try? await Task.sleep(for: .milliseconds(150))
      while NSEvent.pressedMouseButtons & 1 != 0, Date() < deadline {
        try? await Task.sleep(for: .milliseconds(50))
      }
      guard Date() < deadline else { return }
      let point = NSEvent.mouseLocation
      try? await Task.sleep(for: .milliseconds(400))
      completion(point)
    }
  }

  /// True when a point sits on the open island or a floating tray (a drag that ended there stayed home).
  static func isOverTray(_ point: CGPoint) -> Bool {
    NotchShelfController.shared.islandContains(point) || FloatingBasketController.shared.containsTray(at: point)
  }
}
