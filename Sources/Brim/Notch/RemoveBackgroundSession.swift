import AppKit
import Foundation
import ImageIO

/// The Remove Background run: images go in, each one is cut out right away, one after another.
/// It lives outside the widget view because the island collapses (and drops the view) while the
/// file picker is up.
@MainActor
final class RemoveBackgroundSession: ObservableObject {
  struct Item: Identifiable {
    enum State: Equatable {
      case waiting, working
      case done(URL)
      case failed(String)
    }

    let id = UUID()
    let source: URL
    var state: State = .waiting
    /// A small render of the cutout, alpha kept, for the card.
    var preview: CGImage?

    var output: URL? {
      if case .done(let url) = state { return url }
      return nil
    }
  }

  /// Cuts the background out of one image and returns the new PNG.
  typealias Processor = @Sendable (URL, TransformOutputPolicy) async throws -> URL

  static let shared = RemoveBackgroundSession()

  @Published private(set) var items: [Item] = []
  private let process: Processor
  private let policy: () -> TransformOutputPolicy
  private var worker: Task<Void, Never>?

  init(
    process: @escaping Processor = RemoveBackgroundSession.cutout,
    policy: @escaping () -> TransformOutputPolicy = { AppSettings.shared.transformOutputPolicy }
  ) {
    self.process = process
    self.policy = policy
  }

  // MARK: State

  var results: [URL] { items.compactMap(\.output) }
  var isWorking: Bool { items.contains { $0.state == .waiting || $0.state == .working } }
  var failureCount: Int { items.filter { if case .failed = $0.state { true } else { false } }.count }

  /// One line under the cards: what is happening, or where the cutouts went.
  var status: String {
    let finished = items.count - items.filter { $0.state == .waiting || $0.state == .working }.count
    if isWorking {
      return items.count == 1 ? "Removing background…" : "Removing background… \(finished + 1) of \(items.count)"
    }
    let saved = results.count
    if failureCount > 0 { return saved == 0 ? "Couldn’t remove the background" : "\(saved) saved · \(failureCount) failed" }
    let place = policy().destination == .downloads ? "to Downloads" : (saved == 1 ? "next to the original" : "next to the originals")
    return saved == 1 ? "Saved \(place)" : "\(saved) saved \(place)"
  }

  // MARK: Actions

  /// Queues the images among `urls` (anything else, and repeats, are skipped) and starts on them.
  /// Returns how many were queued.
  @discardableResult
  func add(_ urls: [URL]) -> Int {
    var known = Set(items.map(\.source.standardizedFileURL))
    var fresh: [Item] = []
    for url in urls where TransformFileKind(url: url) == .image && known.insert(url.standardizedFileURL).inserted {
      fresh.append(Item(source: url))
    }
    guard !fresh.isEmpty else { return 0 }
    items += fresh
    drain()
    return fresh.count
  }

  /// Back to the empty drop zone. A cutout already being made still lands on disk.
  func clear() {
    worker?.cancel()
    worker = nil
    items = []
  }

  /// Puts one cutout on the pasteboard as a PNG and as a file, so it pastes into apps and Finder.
  func copy(_ url: URL, to pasteboard: NSPasteboard = .general) {
    let item = NSPasteboardItem()
    if let data = try? Data(contentsOf: url) { item.setData(data, forType: .png) }
    item.setString(url.absoluteString, forType: .fileURL)
    pasteboard.clearContents()
    pasteboard.writeObjects([item])
  }

  func reveal(_ urls: [URL]? = nil) {
    let targets = urls ?? results
    guard !targets.isEmpty else { return }
    NSWorkspace.shared.activateFileViewerSelecting(targets)
  }

  /// Waits for the queue to empty (tests).
  func finish() async {
    await worker?.value
  }

  // MARK: Work

  private func drain() {
    guard worker == nil else { return }
    worker = Task { [process, policy] in
      // A worker cancelled by `clear()` must never pick up images added after it.
      while !Task.isCancelled, let index = items.firstIndex(where: { $0.state == .waiting }) {
        let id = items[index].id, source = items[index].source
        items[index].state = .working
        let outputPolicy = policy()
        let outcome = await Task.detached(priority: .userInitiated) { () -> (Item.State, CGImage?) in
          do {
            let output = try await process(source, outputPolicy)
            return (.done(output), Self.preview(of: output))
          } catch {
            return (.failed(Self.message(for: error)), nil)
          }
        }.value
        guard !Task.isCancelled else { return }
        if let at = items.firstIndex(where: { $0.id == id }) {
          items[at].state = outcome.0
          items[at].preview = outcome.1
        }
      }
      // After `clear()` the slot may already hold the next run's worker.
      if !Task.isCancelled { worker = nil }
    }
  }

  nonisolated static func cutout(_ source: URL, policy: TransformOutputPolicy) async throws -> URL {
    let context = TransformContext(policy: policy)
    let outputs = try await TransformEngine.perform(
      .removeBackground, sources: [source], options: TransformOptions(), context: context)
    guard let output = outputs.first else { throw TransformError.failed("Couldn’t save the cutout.") }
    return output
  }

  nonisolated static func preview(of url: URL, maxPixels: Int = 480) -> CGImage? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: maxPixels,
    ]
    return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
  }

  /// Short, human wording for the card; Vision's own errors are long and technical.
  nonisolated static func message(for error: Error) -> String {
    if case FileTrayError.failed(let text) = error, text.hasPrefix("No subject") { return "No subject found" }
    if case FileTrayError.notImage = error { return "Not a readable image" }
    let text = error.localizedDescription
    return text.count > 60 ? "Couldn’t remove the background" : text
  }
}
