import AppKit
import Combine
import SwiftUI

/// State of the launcher panel: the query, the rows, the selection and the activation flow.
@MainActor
final class ThunderstormModel: ObservableObject {
  @Published var query = "" { didSet { if query != oldValue { queryChanged() } } }
  @Published private(set) var results: [ThunderResult] = []
  @Published var selection = 0
  /// A destructive row waiting for a second Return.
  @Published private(set) var confirming: ThunderResult?
  @Published private(set) var notice: String?

  var onDismiss: () -> Void = {}
  var onPaste: (String) -> Void = { _ in }

  private let settings: AppSettings
  private let store: ClipboardStore
  private let fileSearch = ThunderFileSearch()
  private var apps: [InstalledApp] = []
  private var files: [URL] = []
  private var debounce: Task<Void, Never>?

  init(settings: AppSettings = .shared, store: ClipboardStore? = nil, apps: [InstalledApp]? = nil) {
    self.settings = settings
    self.store = store ?? ClipboardStore.shared
    if let apps { self.apps = apps }
    fileSearch.onResults = { [weak self] urls in
      self?.files = urls
      self?.rebuild()
    }
    if apps == nil { Task { [weak self] in await self?.loadApps() } }
    rebuild()
  }

  var panelHeight: CGFloat {
    let rows = CGFloat(max(results.count, notice == nil ? 0 : 1))
    return 62 + (rows > 0 ? rows * 46 + 14 : 0) + 30
  }

  private func loadApps() async {
    apps = await InstalledApps.shared.all()
    rebuild()
  }

  private func queryChanged() {
    confirming = nil
    notice = nil
    selection = 0
    rebuild()
    debounce?.cancel()
    guard settings.thunderstormSearchFiles else { return }
    let text = query
    debounce = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(160))
      guard !Task.isCancelled else { return }
      self?.files = []
      self?.fileSearch.search(text)
    }
  }

  func rebuild() {
    var sources = ThunderSources()
    sources.apps = apps
    sources.files = settings.thunderstormSearchFiles ? files : []
    sources.clipboard = settings.thunderstormSearchClipboard ? store.entries : []
    sources.quicklinks = settings.thunderstormQuicklinks
    sources.snippets = settings.thunderstormSnippets
    sources.systemCommands = settings.thunderstormSystemCommands ? ThunderSystemCommand.allCases : []
    sources.frecency = settings.thunderstormFrecency
    sources.webTemplate = settings.thunderstormWebTemplate
    sources.clipboardText = NSPasteboard.general.string(forType: .string) ?? ""
    results = ThunderResults.build(query: query, sources: sources)
    selection = min(selection, max(0, results.count - 1))
  }

  func move(_ delta: Int) {
    guard !results.isEmpty else { return }
    confirming = nil
    selection = (selection + delta + results.count) % results.count
  }

  func activateSelected() {
    guard results.indices.contains(selection) else { return }
    activate(results[selection])
  }

  func activate(index: Int) {
    guard results.indices.contains(index) else { return }
    selection = index
    activate(results[index])
  }

  func activate(_ result: ThunderResult) {
    if case .system(let command) = result.action, command.needsConfirmation, confirming?.id != result.id {
      confirming = result
      return
    }
    confirming = nil
    settings.thunderstormFrecency = ThunderFrecency.recording(result.id, in: settings.thunderstormFrecency, now: .now)
    switch result.action {
    case .open(let url): NSWorkspace.shared.open(url); onDismiss()
    case .openApp(let url): NSWorkspace.shared.openApplication(at: url, configuration: .init()); onDismiss()
    case .copy(let text): copy(text); onDismiss()
    case .paste(let text): onDismiss(); onPaste(text)
    case .clipboardEntry(let id):
      if let entry = store.entries.first(where: { $0.id == id }) { _ = store.copy(entry) }
      onDismiss()
    case .system(let command):
      if let error = ThunderSystemRunner.run(command) {
        notice = error
      } else {
        onDismiss()
      }
    }
  }

  func copyTitleOfSelected() {
    guard results.indices.contains(selection) else { return }
    copy(results[selection].title)
    onDismiss()
  }

  private func copy(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
  }

  deinit { MainActor.assumeIsolated { fileSearch.stop() } }
}
