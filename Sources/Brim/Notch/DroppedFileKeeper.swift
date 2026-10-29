import Foundation

/// Files dragged out of a temporary place (the macOS screenshot thumbnail, the capture card) are
/// deleted soon after the drag, so a lasting copy is taken before the tray or an action gets them.
enum DroppedFileKeeper {
  static let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("Brim/Dropped", isDirectory: true)

  /// The files, with every temporary one swapped for a copy in `folder` (the original when copying fails).
  static func lasting(
    _ urls: [URL], temporary: URL = FileManager.default.temporaryDirectory, folder: URL = folder,
    files: FileManager = .default
  ) -> [URL] {
    let temporaryPath = temporary.resolvingSymlinksInPath().path
    return urls.map { url in
      guard url.isFileURL, url.resolvingSymlinksInPath().path.hasPrefix(temporaryPath) else { return url }
      return keep(url, folder: folder, files: files) ?? url
    }
  }

  /// Copies one file into its own folder under `folder`, named `name` (keeping the extension) when given.
  static func keep(_ url: URL, named name: String? = nil, folder: URL = folder, files: FileManager = .default) -> URL? {
    let fileName = name.map { name in
      let ext = url.pathExtension
      return ext.isEmpty || name.lowercased().hasSuffix(".\(ext.lowercased())") ? name : "\(name).\(ext)"
    } ?? url.lastPathComponent
    let target = folder.appendingPathComponent(UUID().uuidString, isDirectory: true).appendingPathComponent(fileName)
    do {
      try files.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
      try files.copyItem(at: url, to: target)
      return target
    } catch {
      NSLog("Brim: couldn't keep a copy of \(url.lastPathComponent): \(error.localizedDescription)")
      return nil
    }
  }
}
