import AppKit

/// Files a thumbnail writes: "Save" into the folder chosen under Settings > Saving (the Desktop when
/// none is set, as that pane says), and a temporary PNG for dragging into other apps.
@MainActor
enum ThumbnailSaver {
  static let dragFolder = FileManager.default.temporaryDirectory
    .appendingPathComponent("Brim Thumbnails", isDirectory: true)

  /// The folder "Save" writes to.
  static func saveFolder(settings: AppSettings = .shared, files: FileManager = .default) -> URL {
    settings.defaultSaveFolder
      ?? files.urls(for: .desktopDirectory, in: .userDomainMask).first
      ?? files.homeDirectoryForCurrentUser.appendingPathComponent("Desktop", isDirectory: true)
  }

  /// `base.ext`, then `base 2.ext`, `base 3.ext`… until the name is free.
  static func uniqueURL(in folder: URL, baseName: String, ext: String, files: FileManager = .default) -> URL {
    var candidate = folder.appendingPathComponent(baseName).appendingPathExtension(ext)
    var counter = 2
    while files.fileExists(atPath: candidate.path) {
      candidate = folder.appendingPathComponent("\(baseName) \(counter)").appendingPathExtension(ext)
      counter += 1
    }
    return candidate
  }

  /// Writes the image in the default format and records it in History. Returns the file, or nil.
  @discardableResult
  static func save(
    _ image: NSImage, to folder: URL? = nil, date: Date = .now, record: ((HistoryEntry) -> Void)? = nil
  ) -> URL? {
    let settings = AppSettings.shared
    let folder = folder ?? saveFolder()
    let format: ImageEncoder.Format = settings.defaultImageFormat == "jpg" ? .jpg : .png
    let destination = uniqueURL(in: folder, baseName: AppSettings.defaultFileName(date: date), ext: format.fileExtension)
    guard destination.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL else { return nil }
    do {
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      let data = try ImageEncoder.data(
        from: image, format: format,
        preserveTransparency: settings.preserveTransparency, jpgQuality: settings.jpgQuality)
      try data.write(to: destination, options: .withoutOverwriting)
      let entry = HistoryEntry(kind: .save, fileURL: destination, pixelSize: ImageEncoder.pixelSizeString(of: image))
      if let record { record(entry) } else { HistoryStore.shared.add(entry) }
      return destination
    } catch {
      NSLog("Brim: couldn't save the capture thumbnail: \(error.localizedDescription)")
      return nil
    }
  }

  /// A PNG named like a saved screenshot, in its own scratch folder; copies older than an hour go.
  static func dragFile(for image: NSImage, date: Date = .now) -> URL? {
    ImageDragExport.removeStale(in: dragFolder)
    let folder = dragFolder.appendingPathComponent(UUID().uuidString, isDirectory: true)
    do {
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      let url = folder.appendingPathComponent(AppSettings.defaultFileName(date: date)).appendingPathExtension("png")
      try ImageEncoder.pngDataPreservingAlpha(from: image).write(to: url, options: .withoutOverwriting)
      return url
    } catch {
      NSLog("Brim: couldn't prepare the dragged capture: \(error.localizedDescription)")
      return nil
    }
  }
}
