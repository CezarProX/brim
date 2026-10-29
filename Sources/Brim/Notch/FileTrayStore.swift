import AppKit
import Combine
import ImageIO
import UniformTypeIdentifiers
import Vision

/// A file parked in the tray. The tray keeps references, never copies of the file.
struct FileTrayItem: Codable, Identifiable, Equatable {
  let id: UUID
  let addedAt: Date
  let bookmark: Data
  /// Last known path, used when a bookmark can no longer be resolved.
  let path: String
  /// Pinned items stay at the front and survive the retention clean-up.
  var pinned = false

  init(id: UUID, addedAt: Date, bookmark: Data, path: String, pinned: Bool = false) {
    self.id = id
    self.addedAt = addedAt
    self.bookmark = bookmark
    self.path = path
    self.pinned = pinned
  }

  private enum CodingKeys: String, CodingKey { case id, addedAt, bookmark, path, pinned }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    id = try values.decode(UUID.self, forKey: .id)
    addedAt = try values.decode(Date.self, forKey: .addedAt)
    bookmark = try values.decode(Data.self, forKey: .bookmark)
    path = try values.decode(String.self, forKey: .path)
    pinned = try values.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
  }

  var fallbackURL: URL { URL(fileURLWithPath: path) }
}

/// Image formats the tray converts to, on device, with ImageIO.
enum FileTrayImageFormat: String, CaseIterable, Identifiable {
  case png = "PNG", jpeg = "JPEG", heic = "HEIC", tiff = "TIFF"
  var id: String { rawValue }
  var type: UTType {
    switch self {
    case .png: .png
    case .jpeg: .jpeg
    case .heic: .heic
    case .tiff: .tiff
    }
  }
  var fileExtension: String { type.preferredFilenameExtension ?? rawValue.lowercased() }
}

enum FileTrayError: LocalizedError {
  case missing, notImage, failed(String)
  var errorDescription: String? {
    switch self {
    case .missing: "The file is no longer where it was."
    case .notImage: "This file isn’t an image."
    case .failed(let message): message
    }
  }
}

@MainActor
final class FileTrayStore: ObservableObject {
  static let shared = FileTrayStore(
    flashes: .shared, retention: { AppSettings.shared.trayRetention },
    protectOriginals: { AppSettings.shared.trayProtectOriginals })
  static let maximumItems = 100
  @Published private(set) var items: [FileTrayItem] = []
  @Published private(set) var message: String?
  private let directory: URL
  private let files = FileManager.default
  private var metadataURL: URL { directory.appendingPathComponent("tray.json") }
  /// Where tray changes are announced; only the app-wide tray announces.
  private let flashes: IslandFlashCenter?
  /// How long references stay; read each time so a settings change applies at once.
  private let retention: () -> FileTrayRetention
  /// When on, edits that would touch the original (rename) work on a copy instead.
  private let protectOriginals: () -> Bool
  private var pruneTask: Task<Void, Never>?

  init(
    directory: URL? = nil, flashes: IslandFlashCenter? = nil,
    retention: @escaping () -> FileTrayRetention = { .never },
    protectOriginals: @escaping () -> Bool = { false }
  ) {
    self.flashes = flashes
    self.retention = retention
    self.protectOriginals = protectOriginals
    self.directory =
      directory
      ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Brim/Tray", isDirectory: true)
    load()
    pruneExpired()
    if flashes != nil { startPruning() }
  }

  deinit { pruneTask?.cancel() }

  // MARK: Retention

  /// Drops references older than the retention window; returns how many went.
  @discardableResult
  func pruneExpired(now: Date = .now) -> Int {
    let kept = FileTrayRetention.kept(items, retention: retention(), now: now)
    guard kept.count != items.count else { return 0 }
    let removed = items.count - kept.count
    update(kept)
    return removed
  }

  private func startPruning() {
    pruneTask = Task { @MainActor [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(60))
        self?.pruneExpired()
      }
    }
  }

  // MARK: Items

  func url(for item: FileTrayItem) -> URL {
    var stale = false
    if let url = try? URL(
      resolvingBookmarkData: item.bookmark, options: [.withoutUI], bookmarkDataIsStale: &stale)
    {
      return url
    }
    return item.fallbackURL
  }

  func exists(_ item: FileTrayItem) -> Bool { files.fileExists(atPath: url(for: item).path) }

  /// Adds files that exist and aren't already parked; returns how many were added.
  @discardableResult
  func add(_ urls: [URL], now: Date = .now) -> Int {
    let known = Set(items.map { url(for: $0).standardizedFileURL.path })
    var added: [FileTrayItem] = []
    for url in urls where url.isFileURL {
      let standard = url.standardizedFileURL
      guard files.fileExists(atPath: standard.path), !known.contains(standard.path),
        !added.contains(where: { $0.path == standard.path }),
        let bookmark = try? standard.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
      else { continue }
      added.append(FileTrayItem(id: UUID(), addedAt: now, bookmark: bookmark, path: standard.path))
    }
    guard !added.isEmpty else { return 0 }
    update(FileTrayOrdering.arranged(added + items))
    flashes?.show("\(items.count)", symbol: "tray.and.arrow.down.fill", tint: .blue)
    return added.count
  }

  /// Accepts file drops from Finder or any app (promised screenshots too, and temporary files
  /// are kept as lasting copies); returns false when nothing is a file.
  func drop(_ providers: [NSItemProvider]) -> Bool {
    FileDropLoader.load(providers) { [weak self] urls in self?.add(DroppedFileKeeper.lasting(urls)) }
  }

  func remove(_ ids: Set<UUID>) { update(items.filter { !ids.contains($0.id) }) }

  /// Pins the items, or unpins them when every one is already pinned.
  func togglePin(_ ids: Set<UUID>) {
    let targets = items.filter { ids.contains($0.id) }
    guard !targets.isEmpty else { return }
    let pin = !targets.allSatisfy(\.pinned)
    var next = items
    for index in next.indices where ids.contains(next[index].id) { next[index].pinned = pin }
    update(FileTrayOrdering.arranged(next))
    report(pin ? "Pinned" : "Unpinned")
  }
  func clear() { update([]) }
  /// Puts back a list taken from `items` earlier (the filmed demo hides the real Tray meanwhile).
  func restore(_ saved: [FileTrayItem]) { update(saved) }

  /// Total size of the parked files, skipping any that moved away.
  func totalBytes(of selection: [FileTrayItem]? = nil) -> Int64 {
    (selection ?? items).reduce(0) { total, item in
      let size = (try? url(for: item).resourceValues(forKeys: [.fileSizeKey, .totalFileAllocatedSizeKey]))
        .flatMap { $0.fileSize.map(Int64.init) ?? $0.totalFileAllocatedSize.map(Int64.init) } ?? 0
      return total + size
    }
  }

  // MARK: Drag-out

  /// The provider for dragging a tile out. Honors Protect originals, and when "remove after drag
  /// out" is on, forgets the item once the drag ends away from the trays.
  func dragProvider(for item: FileTrayItem) -> NSItemProvider {
    let settings = AppSettings.shared
    if settings.trayRemoveAfterDragOut, !item.pinned {
      TrayDragOut.trackRelease { [weak self] point in
        let stay = TrayDragOut.isOverTray(point)
        if DragOutPolicy.shouldRemove(enabled: true, releasedOnTray: stay, pinned: false) {
          self?.remove([item.id] as Set<UUID>)
        }
      }
    }
    return TrayDragOut.provider(for: url(for: item), protect: settings.trayProtectOriginals)
  }

  // MARK: Actions

  func open(_ selection: [FileTrayItem]) {
    selection.forEach { NSWorkspace.shared.open(url(for: $0)) }
  }

  func reveal(_ selection: [FileTrayItem]) {
    NSWorkspace.shared.activateFileViewerSelecting(selection.map(url(for:)))
  }

  func copy(_ selection: [FileTrayItem]) {
    let board = NSPasteboard.general
    board.clearContents()
    board.writeObjects(selection.map { url(for: $0) as NSURL })
    report("Copied \(selection.count == 1 ? "1 file" : "\(selection.count) files")")
  }

  func airDrop(_ selection: [FileTrayItem]) {
    guard let service = NSSharingService(named: .sendViaAirDrop) else { return }
    let urls = selection.map(url(for:))
    guard service.canPerform(withItems: urls) else {
      report("AirDrop isn’t available right now")
      return
    }
    service.perform(withItems: urls)
  }

  func rename(_ item: FileTrayItem, to name: String) {
    let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty, !clean.contains("/"), !clean.hasPrefix(".") else {
      report("Use a name without slashes")
      return
    }
    let source = url(for: item)
    let target = source.deletingLastPathComponent().appendingPathComponent(clean)
    do {
      if protectOriginals() {
        try files.copyItem(at: source, to: target)
        replace(item, with: target)
        report("Renamed a copy; the original is untouched")
        return
      }
      try files.moveItem(at: source, to: target)
      replace(item, with: target)
      report("Renamed")
    } catch { report(error.localizedDescription) }
  }

  /// Zips the selection next to the first file and parks the archive in the tray.
  func zip(_ selection: [FileTrayItem]) async {
    let urls = selection.map(url(for:)).filter { files.fileExists(atPath: $0.path) }
    guard let first = urls.first else { return report(FileTrayError.missing.localizedDescription) }
    let base = urls.count == 1 ? first.deletingPathExtension().lastPathComponent : "Archive"
    let target = Self.uniqueURL(
      in: first.deletingLastPathComponent(), name: base, fileExtension: "zip", files: files)
    do {
      try await Task.detached(priority: .userInitiated) {
        try Self.runZip(urls, to: target)
      }.value
      add([target])
      report("Created \(target.lastPathComponent)")
    } catch { report(error.localizedDescription) }
  }

  /// Writes converted copies beside each image and parks them in the tray.
  func convert(_ selection: [FileTrayItem], to format: FileTrayImageFormat) async {
    let urls = selection.map(url(for:))
    let results = await Task.detached(priority: .userInitiated) { () -> [Result<URL, Error>] in
      urls.map { source in Result { try Self.convertImage(source, to: format) } }
    }.value
    let made = results.compactMap { try? $0.get() }
    add(made)
    report(made.isEmpty ? "Only images can be converted" : "Converted \(made.count) to \(format.rawValue)")
  }

  /// Lifts the subject out of each photo with on-device Vision and saves a transparent PNG.
  func removeBackground(_ selection: [FileTrayItem]) async {
    let urls = selection.map(url(for:))
    let results = await Task.detached(priority: .userInitiated) { () -> [Result<URL, Error>] in
      urls.map { source in Result { try Self.cutout(source) } }
    }.value
    let made = results.compactMap { try? $0.get() }
    add(made)
    report(made.isEmpty ? "No subject found to lift" : "Removed background from \(made.count)")
  }

  // MARK: File work (off the main actor)

  nonisolated static func uniqueURL(
    in folder: URL, name: String, fileExtension: String, files: FileManager = .default
  ) -> URL {
    var candidate = folder.appendingPathComponent(name).appendingPathExtension(fileExtension)
    var index = 2
    while files.fileExists(atPath: candidate.path) {
      candidate = folder.appendingPathComponent("\(name) \(index)").appendingPathExtension(fileExtension)
      index += 1
    }
    return candidate
  }

  nonisolated private static func runZip(_ urls: [URL], to target: URL) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
    process.currentDirectoryURL = urls[0].deletingLastPathComponent()
    // Relative names keep the archive free of absolute paths.
    process.arguments = ["-r", "-q", "-y", target.path] + urls.map(\.lastPathComponent)
    let sameFolder = urls.allSatisfy {
      $0.deletingLastPathComponent().path == urls[0].deletingLastPathComponent().path
    }
    if !sameFolder {
      process.arguments = ["-r", "-q", "-j", "-y", target.path] + urls.map(\.path)
    }
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
      throw FileTrayError.failed("Couldn’t create the ZIP archive.")
    }
  }

  nonisolated static func convertImage(_ source: URL, to format: FileTrayImageFormat) throws -> URL {
    guard let input = CGImageSourceCreateWithURL(source as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(input, 0, nil)
    else { throw FileTrayError.notImage }
    let target = uniqueURL(
      in: source.deletingLastPathComponent(), name: source.deletingPathExtension().lastPathComponent,
      fileExtension: format.fileExtension)
    try write(image, to: target, type: format.type)
    return target
  }

  nonisolated static func cutout(_ source: URL) throws -> URL {
    let masked = try cutoutImage(source)
    let target = uniqueURL(
      in: source.deletingLastPathComponent(),
      name: source.deletingPathExtension().lastPathComponent + " cutout", fileExtension: "png")
    try write(masked, to: target, type: .png)
    return target
  }

  /// The subject of a photo on a transparent background, found with on-device Vision.
  nonisolated static func cutoutImage(_ source: URL) throws -> CGImage {
    guard let input = CGImageSourceCreateWithURL(source as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(input, 0, nil)
    else { throw FileTrayError.notImage }
    let request = VNGenerateForegroundInstanceMaskRequest()
    let handler = VNImageRequestHandler(cgImage: image)
    try handler.perform([request])
    guard let observation = request.results?.first else {
      throw FileTrayError.failed("No subject found.")
    }
    let buffer = try observation.generateMaskedImage(
      ofInstances: observation.allInstances, from: handler, croppedToInstancesExtent: true)
    let ciImage = CIImage(cvPixelBuffer: buffer)
    guard let masked = CIContext().createCGImage(ciImage, from: ciImage.extent) else {
      throw FileTrayError.failed("Couldn’t render the cutout.")
    }
    return masked
  }

  nonisolated private static func write(_ image: CGImage, to target: URL, type: UTType) throws {
    guard
      let destination = CGImageDestinationCreateWithURL(
        target as CFURL, type.identifier as CFString, 1, nil)
    else { throw FileTrayError.failed("This format isn’t supported on this Mac.") }
    CGImageDestinationAddImage(
      destination, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
    guard CGImageDestinationFinalize(destination) else {
      throw FileTrayError.failed("Couldn’t write \(target.lastPathComponent).")
    }
  }

  // MARK: Persistence

  private func replace(_ item: FileTrayItem, with target: URL) {
    guard let index = items.firstIndex(of: item),
      let bookmark = try? target.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    else { return }
    var updated = items
    updated[index] = FileTrayItem(
      id: item.id, addedAt: item.addedAt, bookmark: bookmark, path: target.path, pinned: item.pinned)
    update(updated)
  }

  private func update(_ next: [FileTrayItem]) {
    items = next
    do {
      try files.createDirectory(
        at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
      try JSONEncoder().encode(next).write(to: metadataURL, options: .atomic)
      try files.setAttributes([.posixPermissions: 0o600], ofItemAtPath: metadataURL.path)
    } catch { report("Couldn’t save the tray. \(error.localizedDescription)") }
  }

  private func load() {
    guard let data = try? Data(contentsOf: metadataURL), data.count < 2_000_000,
      let decoded = try? JSONDecoder().decode([FileTrayItem].self, from: data)
    else { return }
    items = FileTrayOrdering.arranged(decoded)
  }

  private func report(_ text: String) {
    message = text
    let current = text
    Task { @MainActor [weak self] in
      try? await Task.sleep(for: .seconds(3))
      if self?.message == current { self?.message = nil }
    }
  }
}
