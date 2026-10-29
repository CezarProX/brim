import AppKit
import Foundation

/// Live editing of a vault's Markdown files: pick a folder, list, edit with debounced save, daily note.
/// With no folder picked by hand it follows the Obsidian app: the vault Obsidian has open is used
/// automatically and re-checked on every reload.
@MainActor
final class ObsidianModel: ObservableObject {
  static let shared = ObsidianModel()
  @Published private(set) var vault: ObsidianVault?
  @Published private(set) var files: [ObsidianFile] = []
  @Published private(set) var selectedPath: String?
  @Published var text = ""
  @Published private(set) var error: String?
  /// Vaults registered in the Obsidian app, open one first.
  @Published private(set) var knownVaults: [ObsidianKnownVault] = []
  /// True when the vault comes from the Obsidian app rather than a folder picked by hand.
  @Published private(set) var followsObsidian = true
  private let obsidianConfig: URL?
  private var saveTask: Task<Void, Never>?
  private var loadedText = ""

  /// `obsidianConfig` is Obsidian's vault registry; nil turns the automatic link off (tests).
  init(vaultPath: String? = AppSettings.shared.obsidianVaultPath,
       obsidianConfig: URL? = ObsidianAppLink.defaultConfigURL) {
    self.obsidianConfig = obsidianConfig
    knownVaults = obsidianConfig.map { ObsidianAppLink.knownVaults(configURL: $0) } ?? []
    if let vaultPath, FileManager.default.fileExists(atPath: vaultPath) {
      vault = ObsidianVault(root: URL(fileURLWithPath: vaultPath))
      followsObsidian = false
    } else {
      vault = knownVaults.first.map { ObsidianVault(root: URL(fileURLWithPath: $0.path)) }
    }
    files = vault?.list() ?? []
  }

  /// Opens a folder chooser; the choice is remembered.
  func chooseVault() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.message = "Choose your Obsidian vault folder"
    guard panel.runModal() == .OK, let url = panel.url else { return }
    setVault(url)
  }

  /// Pins a folder by hand; it stays until `followObsidian()` is called.
  func setVault(_ url: URL) {
    AppSettings.shared.obsidianVaultPath = url.path
    followsObsidian = false
    switchVault(to: ObsidianVault(root: url))
  }

  func useKnownVault(_ known: ObsidianKnownVault) { setVault(URL(fileURLWithPath: known.path)) }

  /// Drops the hand-picked folder and goes back to whatever vault the Obsidian app has open.
  func followObsidian() {
    AppSettings.shared.obsidianVaultPath = nil
    followsObsidian = true
    knownVaults = obsidianConfig.map { ObsidianAppLink.knownVaults(configURL: $0) } ?? []
    switchVault(to: knownVaults.first.map { ObsidianVault(root: URL(fileURLWithPath: $0.path)) })
  }

  /// Shows the selected note (or the vault) in the Obsidian app.
  func openInObsidian() {
    guard let vault else { return }
    flush()
    error = ObsidianAppLink.open(vaultRoot: vault.root, relativePath: selectedPath) ? nil : "Obsidian isn’t installed."
  }

  private func switchVault(to next: ObsidianVault?) {
    flush()
    vault = next
    selectedPath = nil
    text = ""
    loadedText = ""
    files = vault?.list() ?? []
  }

  func reload() {
    if let obsidianConfig {
      knownVaults = ObsidianAppLink.knownVaults(configURL: obsidianConfig)
      if followsObsidian, let open = knownVaults.first,
        ObsidianVault(root: URL(fileURLWithPath: open.path)).root != vault?.root {
        switchVault(to: ObsidianVault(root: URL(fileURLWithPath: open.path)))
      }
    }
    files = vault?.list() ?? []
    if let selectedPath, let vault, let fresh = try? vault.read(selectedPath), fresh != loadedText {
      loadedText = fresh
      text = fresh
    }
  }

  func select(_ path: String) {
    flush()
    guard let vault else { return }
    do {
      loadedText = try vault.read(path)
      text = loadedText
      selectedPath = path
      error = nil
    } catch { self.error = "Couldn’t open that note." }
  }

  func openDailyNote() {
    guard let vault else { return }
    do {
      let path = try vault.openDailyNote()
      reload()
      select(path)
    } catch { self.error = "Couldn’t create the daily note." }
  }

  /// Creates an empty "Untitled" note at the top of the vault and opens it.
  func createNote() {
    guard let vault else { return }
    do {
      let path = vault.uniqueNotePath(named: "Untitled")
      try vault.write("", to: path)
      reload()
      select(path)
    } catch { self.error = "Couldn’t create the note." }
  }

  /// Called on every edit; writes 0.6 s after typing stops.
  func edited() {
    saveTask?.cancel()
    saveTask = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(600))
      guard !Task.isCancelled else { return }
      self?.flush()
    }
  }

  func flush() {
    saveTask?.cancel()
    guard let vault, let selectedPath, text != loadedText else { return }
    do {
      try vault.write(text, to: selectedPath)
      loadedText = text
      error = nil
    } catch { self.error = "Couldn’t save to the vault." }
  }
}
