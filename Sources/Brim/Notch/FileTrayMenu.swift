import AppKit
import SwiftUI

/// The right-click menu for files in the tray: Copy, Open, Show in Finder, Move to, Open With,
/// Share, Save All, Transform ▸, Create ZIP, Create Folder, Rename and Remove from File Tray.
@MainActor
struct FileTrayMenu: View {
  let items: [FileTrayItem]
  let store: FileTrayStore
  let rename: (FileTrayItem) -> Void
  let run: (@escaping @MainActor () async -> Void) -> Void
  let remove: ([FileTrayItem]) -> Void

  private var urls: [URL] { items.map(store.url(for:)) }
  private var countSuffix: String { items.count > 1 ? " (\(items.count))" : "" }

  var body: some View {
    Button("Copy") { store.copy(items) }
    Button("Open") { store.open(items) }
    Button(items.allSatisfy(\.pinned) ? "Unpin" : "Pin to Tray") { store.togglePin(Set(items.map(\.id))) }
    Button("Show in Finder") { store.reveal(items) }
    Divider()
    Menu(AppSettings.shared.trayProtectOriginals ? "Copy to" : "Move to") {
      ForEach(FileTrayActions.moveDestinations, id: \.self) { folder in
        Button(FileManager.default.displayName(atPath: folder.path)) { FileTrayActions.move(urls, to: folder) }
      }
      Divider()
      Button("Other…") { if let folder = FileTrayActions.chooseFolder(prompt: "Move") { FileTrayActions.move(urls, to: folder) } }
    }
    Menu("Open With") {
      let apps = FileTrayActions.applications(for: urls)
      ForEach(apps, id: \.self) { app in
        Button(FileManager.default.displayName(atPath: app.path)) { FileTrayActions.open(urls, with: app) }
      }
      if apps.isEmpty { Text("No apps") }
    }
    Menu("Share") {
      ForEach(FileTrayActions.shareServices, id: \.title) { service in
        Button(service.title) {
          if service.name == .composeEmail { MailAppChoice.send(urls) } else { FileTrayActions.share(urls, with: service.name) }
        }
      }
      if AppSettings.shared.localSendEnabled {
        Divider()
        Button("LocalSend…") { NotchShelfController.shared.presentLocalSend(urls) }
      }
    }
    Button("Save All\(countSuffix)…") {
      if let folder = FileTrayActions.chooseFolder(prompt: "Save") { FileTrayActions.copy(urls, to: folder) }
    }
    Divider()
    transformMenu
    Divider()
    Button("Create ZIP") { run { await store.zip(items) } }
    Button("Create Folder\(countSuffix)") { FileTrayActions.makeFolder(with: urls, store: store) }
    if items.count == 1, let item = items.first {
      Button("Rename…") { rename(item) }
    }
    Divider()
    Button("Remove from File Tray", role: .destructive) { remove(items) }
    Button("Clear File Tray", role: .destructive) { remove(store.items) }
  }

  /// Every Transform operation these files support; picking one opens the Transform panel on it.
  @ViewBuilder private var transformMenu: some View {
    let operations = TransformOperation.available(for: urls)
    Menu("Transform") {
      ForEach(operations) { operation in
        Button {
          TransformLaunchRequest.shared.operation = operation
          NotchShelfController.shared.presentConvert(urls)
        } label: {
          Label("\(operation.title)…", systemImage: operation.symbol)
        }
      }
    }
    .disabled(operations.isEmpty)
  }
}

/// File operations behind the tray's menu. Failures surface as an island flash.
@MainActor
enum FileTrayActions {
  struct ShareService {
    let title: String
    let name: NSSharingService.Name
  }

  static let shareServices = [
    ShareService(title: "AirDrop", name: .sendViaAirDrop),
    ShareService(title: "Mail", name: .composeEmail),
    ShareService(title: "Messages", name: .composeMessage),
  ]

  static var moveDestinations: [URL] {
    [FileManager.SearchPathDirectory.desktopDirectory, .documentDirectory, .downloadsDirectory]
      .compactMap { FileManager.default.urls(for: $0, in: .userDomainMask).first }
  }

  /// Apps that open every file, default app first, at most eight.
  static func applications(for urls: [URL]) -> [URL] {
    guard let first = urls.first else { return [] }
    let shared = urls.dropFirst().reduce(Set(NSWorkspace.shared.urlsForApplications(toOpen: first))) {
      $0.intersection(NSWorkspace.shared.urlsForApplications(toOpen: $1))
    }
    let ordered = NSWorkspace.shared.urlsForApplications(toOpen: first).filter(shared.contains)
    return Array(ordered.prefix(8))
  }

  static func open(_ urls: [URL], with app: URL) {
    NSWorkspace.shared.open(urls, withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration()) { _, error in
      guard let error else { return }
      Task { @MainActor in flash("Couldn’t open", detail: error.localizedDescription) }
    }
  }

  static func share(_ urls: [URL], with name: NSSharingService.Name) {
    guard let service = NSSharingService(named: name), service.canPerform(withItems: urls) else {
      flash("Sharing isn’t available right now")
      return
    }
    service.perform(withItems: urls)
  }

  static func chooseFolder(prompt: String) -> URL? {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.canCreateDirectories = true
    panel.prompt = prompt
    return panel.runModal() == .OK ? panel.url : nil
  }

  /// Moves the files; the tray keeps tracking them through their bookmarks.
  static func move(_ urls: [URL], to folder: URL) {
    if AppSettings.shared.trayProtectOriginals {
      transfer(urls, to: folder, verb: "Copied") { try FileManager.default.copyItem(at: $0, to: $1) }
    } else {
      transfer(urls, to: folder, verb: "Moved") { try FileManager.default.moveItem(at: $0, to: $1) }
    }
  }

  static func copy(_ urls: [URL], to folder: URL) {
    transfer(urls, to: folder, verb: "Saved") { try FileManager.default.copyItem(at: $0, to: $1) }
  }

  /// Copies the files into a new folder beside the first one and parks the folder in the tray.
  static func makeFolder(with urls: [URL], store: FileTrayStore) {
    guard let first = urls.first else { return }
    let folder = FileTrayStore.uniqueURL(in: first.deletingLastPathComponent(), name: "New Folder", fileExtension: "")
    do {
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
      for url in urls {
        try FileManager.default.copyItem(at: url, to: folder.appendingPathComponent(url.lastPathComponent))
      }
      _ = store.add([folder])
      flash("Created \(folder.lastPathComponent)")
    } catch {
      flash("Couldn’t create the folder", detail: error.localizedDescription)
    }
  }

  private static func transfer(
    _ urls: [URL], to folder: URL, verb: String, operation: (URL, URL) throws -> Void
  ) {
    var done = 0
    for url in urls where url.deletingLastPathComponent().standardizedFileURL != folder.standardizedFileURL {
      let target = FileTrayStore.uniqueURL(
        in: folder, name: url.deletingPathExtension().lastPathComponent, fileExtension: url.pathExtension)
      do {
        try operation(url, target)
        done += 1
      } catch {
        flash("Couldn’t finish", detail: error.localizedDescription)
        return
      }
    }
    flash("\(verb) \(done == 1 ? "1 file" : "\(done) files")", detail: folder.lastPathComponent)
  }

  private static func flash(_ title: String, detail: String? = nil) {
    IslandFlashCenter.shared.show(title, symbol: "tray.fill", tint: .blue, detail: detail)
  }
}
