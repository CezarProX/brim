import AppKit
import Foundation
import ImageIO

/// Watches the folders chosen in Settings and parks every new file that appears there in the tray.
/// Only names are remembered, so files already in a folder when watching starts are left alone.
@MainActor
final class TrackedFolders {
  static let shared = TrackedFolders()
  private struct Watch {
    let source: DispatchSourceFileSystemObject
    var known: Set<String>
  }
  private var watches: [String: Watch] = [:]
  private var pending: [String: Task<Void, Never>] = [:]

  /// Starts or stops watching so it matches the settings. Safe to call whenever they change.
  func refresh(settings: AppSettings = .shared) {
    let wanted = settings.trackedFoldersEnabled ? TrackedFolderScan.watchable(settings.trackedFolderPaths) : []
    for path in watches.keys where !wanted.contains(path) { stopWatching(path) }
    for path in wanted where watches[path] == nil { startWatching(path) }
  }

  func start() { refresh() }

  func stop() { Array(watches.keys).forEach(stopWatching) }

  private func startWatching(_ path: String) {
    let descriptor = open(path, O_EVTONLY)
    guard descriptor >= 0 else { return }
    let source = DispatchSource.makeFileSystemObjectSource(
      fileDescriptor: descriptor, eventMask: [.write, .rename, .delete], queue: .main)
    source.setEventHandler { [weak self] in
      MainActor.assumeIsolated { self?.folderChanged(path) }
    }
    source.setCancelHandler { close(descriptor) }
    watches[path] = Watch(source: source, known: Set(listing(path).map(\.lastPathComponent)))
    source.resume()
  }

  private func stopWatching(_ path: String) {
    watches[path]?.source.cancel()
    watches[path] = nil
    pending[path]?.cancel()
    pending[path] = nil
  }

  private func listing(_ path: String) -> [URL] {
    let keys: [URLResourceKey] = [.isRegularFileKey, .isPackageKey, .isDirectoryKey]
    let urls = (try? FileManager.default.contentsOfDirectory(
      at: URL(fileURLWithPath: path), includingPropertiesForKeys: keys)) ?? []
    return urls.filter { url in
      let values = try? url.resourceValues(forKeys: Set(keys))
      return values?.isRegularFile == true || values?.isPackage == true || values?.isDirectory == true
    }
  }

  /// Waits for bursts of events (a download writing) to settle, then collects the new files.
  private func folderChanged(_ path: String) {
    pending[path]?.cancel()
    pending[path] = Task { @MainActor [weak self] in
      try? await Task.sleep(for: .seconds(1))
      guard !Task.isCancelled, let self, var watch = self.watches[path] else { return }
      let fresh = TrackedFolderScan.newFiles(current: self.listing(path), known: watch.known)
      watch.known.formUnion(self.listing(path).map(\.lastPathComponent))
      self.watches[path] = watch
      guard !fresh.isEmpty else { return }
      let added = FileTrayStore.shared.add(fresh)
      if added > 0 {
        IslandFlashCenter.shared.show(
          added == 1 ? "Tracked 1 new file" : "Tracked \(added) new files",
          symbol: "folder.badge.plus", tint: .blue, detail: URL(fileURLWithPath: path).lastPathComponent)
      }
      if AppSettings.shared.trackedFoldersAutoOCR { Self.copyText(from: fresh) }
    }
  }

  /// Auto-copy OCR: puts the text of the first readable image on the pasteboard. On-device Vision.
  private static func copyText(from urls: [URL]) {
    let images = urls.filter(FileDropActions.isImage)
    guard let first = images.first else { return }
    Task.detached(priority: .utility) {
      guard let source = CGImageSourceCreateWithURL(first as CFURL, nil),
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
      else { return }
      let text = TextRecognition.recognizeText(in: image)
      guard !text.isEmpty else { return }
      await MainActor.run {
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(text, forType: .string)
        IslandFlashCenter.shared.show("Text copied", symbol: "text.viewfinder", tint: .green, detail: first.lastPathComponent)
      }
    }
  }
}
