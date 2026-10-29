import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Where dragged files can go in the notch, the island and the floating tray.
/// Drop and Transform are always shown; the rest are swappable in Settings.
enum DropTarget: String, CaseIterable, Identifiable {
  case keep, convert, airDrop, copy, zip, openWith, mail, basket, localSend
  var id: String { rawValue }

  var title: String {
    switch self {
    case .keep: "Drop"
    case .convert: "Transform"
    case .airDrop: "AirDrop"
    case .copy: "Copy"
    case .zip: "Zip"
    case .openWith: "Open With…"
    case .mail: "Mail"
    case .basket: "Tray"
    case .localSend: "LocalSend"
    }
  }

  var symbol: String {
    switch self {
    case .keep: "tray.and.arrow.down.fill"
    case .convert: "wand.and.sparkles"
    case .airDrop: "dot.radiowaves.left.and.right"
    case .copy: "doc.on.doc.fill"
    case .zip: "doc.zipper"
    case .openWith: "arrow.up.forward.app.fill"
    case .mail: "envelope.fill"
    case .basket: "basket.fill"
    case .localSend: "paperplane.fill"
    }
  }

  /// Drop and Transform can't be removed.
  static let required: [DropTarget] = [.keep, .convert]
  static let optional: [DropTarget] = [.airDrop, .localSend, .copy, .zip, .openWith, .mail, .basket]
  static let defaultExtras: [DropTarget] = [.airDrop]

  /// Keeps only optional targets, once each, within the limit.
  static func sanitizedExtras(_ targets: [DropTarget], limit: Int = AppSettings.maximumQuickActionExtras) -> [DropTarget] {
    var seen = Set<DropTarget>()
    return Array(targets.filter { optional.contains($0) && seen.insert($0).inserted }.prefix(limit))
  }
}

/// Loads file URLs out of drop providers, then hands them over on the main actor.
/// Besides real files it takes images and movies that the source only promises to write, which is
/// how the macOS screenshot thumbnail drags (a file promise, with no file until the drop asks).
enum FileDropLoader {
  /// What file drop targets accept.
  static let types: [UTType] = [.fileURL, .image, .movie]
  /// The drag a drop target last started loading, so the release fallback doesn't deliver it twice.
  nonisolated(unsafe) static var loadingDrag: Int?

  static func load(_ providers: [NSItemProvider], limit: Int = 50, completion: @escaping @MainActor ([URL]) -> Void) -> Bool {
    let usable = providers.filter { isFile($0) || promisedType(of: $0) != nil }.prefix(limit)
    guard !usable.isEmpty else { return false }
    loadingDrag = NSPasteboard(name: .drag).changeCount
    let group = DispatchGroup()
    let lock = NSLock()
    var urls: [URL] = []
    let collect: (URL?) -> Void = { url in
      guard let url else { return }
      lock.lock()
      urls.append(url)
      lock.unlock()
    }
    for provider in usable {
      group.enter()
      if isFile(provider) {
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
          collect((item as? Data).flatMap { URL(dataRepresentation: $0, relativeTo: nil) } ?? (item as? URL))
          group.leave()
        }
      } else if let type = promisedType(of: provider) {
        _ = provider.loadFileRepresentation(forTypeIdentifier: type) { url, error in
          // The written file is deleted once this returns, so keep a copy first.
          if let error { NSLog("Brim: a dropped file never arrived: \(error.localizedDescription)") }
          collect(url.flatMap { DroppedFileKeeper.keep($0, named: provider.suggestedName) })
          group.leave()
        }
      } else {
        group.leave()
      }
    }
    group.notify(queue: .main) {
      MainActor.assumeIsolated { completion(urls) }
    }
    return true
  }

  private static func isFile(_ provider: NSItemProvider) -> Bool {
    provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
  }

  /// The image or movie type a provider can hand over as a file, when it carries no file URL.
  static func promisedType(of provider: NSItemProvider) -> String? {
    provider.registeredTypeIdentifiers.first { identifier in
      guard let type = UTType(identifier) else { return false }
      return type.conforms(to: .image) || type.conforms(to: .movie)
    }
  }
}

/// What each drop target does with the files it receives.
@MainActor
enum FileDropActions {
  static func keep(_ urls: [URL]) {
    let added = FileTrayStore.shared.add(urls)
    IslandFlashCenter.shared.show(
      added == 1 ? "Kept 1 file" : "Kept \(added) files", symbol: "tray.and.arrow.down.fill", tint: .blue)
  }

  static func airDrop(_ urls: [URL]) {
    guard let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: urls) else {
      IslandFlashCenter.shared.show("AirDrop unavailable", symbol: "dot.radiowaves.left.and.right", tint: .white)
      return
    }
    service.perform(withItems: urls)
  }

  static func basket(_ urls: [URL]) {
    FloatingBasketController.shared.receive(urls)
  }

  /// Writes converted copies beside each image and keeps them in the Shelf.
  static func convert(_ urls: [URL], to format: FileTrayImageFormat) async {
    let made = await Task.detached(priority: .userInitiated) {
      urls.compactMap { try? FileTrayStore.convertImage($0, to: format) }
    }.value
    FileTrayStore.shared.add(made)
    IslandFlashCenter.shared.show(
      made.isEmpty ? "Only images convert" : "Converted to \(format.rawValue)",
      symbol: made.isEmpty ? "exclamationmark.triangle.fill" : "checkmark.circle.fill",
      tint: made.isEmpty ? .orange : .green)
  }

  /// Runs a tile's action. `transform` opens the Transform panel for the files.
  static func perform(_ target: DropTarget, _ urls: [URL], transform: ([URL]) -> Void) {
    switch target {
    case .keep: keep(urls)
    case .convert: transform(urls)
    case .airDrop: airDrop(urls)
    case .copy: copy(urls)
    case .zip: zip(urls)
    case .openWith: openWith(urls)
    case .mail: mail(urls)
    case .basket: basket(urls)
    case .localSend: NotchShelfController.shared.presentLocalSend(urls)
    }
  }

  static func copy(_ urls: [URL]) {
    let board = NSPasteboard.general
    board.clearContents()
    board.writeObjects(urls.map { $0 as NSURL })
    IslandFlashCenter.shared.show(
      urls.count == 1 ? "Copied 1 file" : "Copied \(urls.count) files", symbol: "doc.on.doc.fill", tint: .green)
  }

  static func mail(_ urls: [URL]) { MailAppChoice.send(urls) }

  /// Asks which app to open the files with, then opens them there.
  static func openWith(_ urls: [URL]) {
    let panel = NSOpenPanel()
    panel.message = "Choose an app to open \(urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) files")"
    panel.allowedContentTypes = [.application]
    panel.directoryURL = URL(fileURLWithPath: "/Applications")
    panel.allowsMultipleSelection = false
    NSApp.activate(ignoringOtherApps: true)
    guard panel.runModal() == .OK, let app = panel.url else { return }
    NSWorkspace.shared.open(urls, withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
  }

  /// Zips the files with the user's Transform destination and keeps the archive in the tray.
  static func zip(_ urls: [URL]) {
    Task { @MainActor in
      let policy = AppSettings.shared.transformOutputPolicy
      let context = TransformContext(policy: policy)
      let result = await Task.detached(priority: .userInitiated) { () -> URL? in
        try? ArchiveTransforms.zip(urls, context: context)
      }.value
      if let result { FileTrayStore.shared.add([result]) }
      IslandFlashCenter.shared.show(
        result == nil ? "Couldn’t zip" : "Zipped", symbol: result == nil ? "exclamationmark.triangle.fill" : "doc.zipper",
        tint: result == nil ? .orange : .green)
    }
  }

  static func isImage(_ url: URL) -> Bool {
    (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType?.conforms(to: .image)) ?? false
  }
}

/// A single drop tile: glyph over label, lit while a drag hovers it.
struct DropTargetTile: View {
  let target: DropTarget
  var large = false
  /// The shake panel's bigger, darker tiles (the floating quick actions).
  var floating = false
  let receive: ([URL]) -> Void
  @State private var targeted = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    VStack(spacing: floating ? 12 : large ? 8 : 5) {
      Image(systemName: target.symbol).font(.system(size: floating ? 30 : large ? 22 : 16, weight: floating ? .regular : .semibold))
        .symbolEffect(.bounce, value: targeted)
        .frame(height: floating ? 36 : large ? 28 : 20)
      Text(target.title)
        .font(floating ? .system(size: 16, weight: .semibold) : large ? IslandFont.label.weight(.semibold) : IslandFont.caption.weight(.semibold))
    }
    .foregroundStyle(targeted || floating ? Color.white.opacity(floating && !targeted ? 0.88 : 1) : IslandInk.secondary)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background {
      // Layered glass: the shake panel's tiles sit darker than its glass, the island's lighter.
      GlassCardBackground(
        shape: RoundedRectangle(cornerRadius: floating ? 24 : large ? 16 : 12, style: .continuous),
        fill: targeted ? Color.white.opacity(0.28) : (floating ? Color.black.opacity(0.28) : IslandFill.raised))
    }
    .scaleEffect(targeted && !reduceMotion ? 1.05 : 1)
    .animation(NotchMotion.press(reduceMotion: reduceMotion), value: targeted)
    .onDrop(of: FileDropLoader.types, isTargeted: $targeted) { providers in
      FileDropLoader.load(providers) { urls in receive(urls) }
    }
    .accessibilityLabel(target.title)
  }
}


/// The Quick Actions row: Drop, Transform and the user's extras, as configured in Settings.
/// Drop it into the island's drop mode in place of hard-coded tiles.
struct QuickActionTilesRow: View {
  /// Called with the files when they land on Transform.
  let transform: ([URL]) -> Void
  var columns: Int?
  @State private var targets = AppSettings.shared.quickActionTargets

  var body: some View {
    Group {
      if let columns {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: columns), spacing: 6) {
          tiles
        }
      } else {
        HStack(spacing: IslandSpace.s) { tiles }
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
      let latest = AppSettings.shared.quickActionTargets
      if latest != targets { targets = latest }
    }
  }

  @ViewBuilder
  private var tiles: some View {
    ForEach(targets) { target in
      DropTargetTile(target: target, large: true) { urls in
        FileDropActions.perform(target, urls, transform: transform)
      }
      .frame(height: columns == nil ? nil : 96)
    }
  }
}
