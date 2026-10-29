import AppKit
import UniformTypeIdentifiers
import os

/// Export / import settings, export logs, reset sizes and hard reset. The pure parts live in
/// `SettingsTransfer`; this is the panels, files and processes around it.
@MainActor
enum SettingsUtilities {
  private static let log = Logger(subsystem: "io.github.cezarprox.brim", category: "settings-utilities")

  static var domainName: String { Bundle.main.bundleIdentifier ?? "io.github.cezarprox.brim" }
  static var appVersion: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
  }
  static var buildNumber: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "dev" }

  /// Keys that hold the island and floating-player sizes and spots.
  static let panelSizeKeys = [
    "shellIslandWidthOffset", "shellIslandHeightOffset", "shellIslandVerticalOffset",
    "shellNotchWidthOffset", "shellNotchHeightOffset", "liquidPlayerSize", "liquidPlayerOrigin",
  ]

  // MARK: Export / import

  static func exportSettings() {
    let defaults = AppSettings.shared.defaults
    let domain = defaults.persistentDomain(forName: domainName) ?? [:]
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.json]
    panel.nameFieldStringValue = "Brim Settings.json"
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      try SettingsTransfer.export(domain: domain, appVersion: appVersion).write(to: url, options: .atomic)
      notify("Settings exported", url.lastPathComponent)
    } catch {
      alert("Couldn’t export settings", error.localizedDescription)
    }
  }

  static func importSettings() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.json]
    panel.allowsMultipleSelection = false
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      let data = try Data(contentsOf: url)
      let result = try SettingsTransfer.importSettings(data, into: AppSettings.shared.defaults)
      applyImported()
      notify("Settings imported", "\(result.applied) settings applied" + (result.skipped.isEmpty ? "" : ", \(result.skipped.count) skipped"))
    } catch {
      alert("Couldn’t import settings", error.localizedDescription)
    }
  }

  /// Tells the running features to re-read what the import changed.
  private static func applyImported() {
    NotchShelfController.shared.settingsChanged()
    CommandCenterStore.shared.reload()
    MenuBarController.shared.refresh()
  }

  // MARK: Logs

  /// Collects the last hour of Brim's unified log into a zip on the Desktop.
  static func exportLogs() {
    notify("Collecting logs", "This takes a few seconds.")
    Task.detached(priority: .utility) {
      let result = Result { try collectLogs() }
      await MainActor.run {
        switch result {
        case .success(let url):
          NSWorkspace.shared.activateFileViewerSelecting([url])
          notify("Logs exported", url.lastPathComponent)
        case .failure(let error):
          alert("Couldn’t export logs", error.localizedDescription)
        }
      }
    }
  }

  nonisolated private static func collectLogs() throws -> URL {
    let fm = FileManager.default
    let stamp = ISO8601DateFormatter().string(from: .now).replacingOccurrences(of: ":", with: "-")
    let folder = fm.temporaryDirectory.appendingPathComponent("Brim-Logs-\(stamp)")
    try fm.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: folder) }
    let logFile = folder.appendingPathComponent("brim.log")
    fm.createFile(atPath: logFile.path, contents: nil)
    let handle = try FileHandle(forWritingTo: logFile)
    defer { try? handle.close() }
    try run("/usr/bin/log", ["show", "--predicate", "process == \"Brim\"", "--last", "1h", "--style", "compact"], output: handle)
    let desktop = fm.urls(for: .desktopDirectory, in: .userDomainMask).first ?? fm.homeDirectoryForCurrentUser
    let zip = desktop.appendingPathComponent("Brim-Logs-\(stamp).zip")
    try run("/usr/bin/ditto", ["-c", "-k", "--keepParent", folder.path, zip.path], output: nil)
    return zip
  }

  nonisolated private static func run(_ path: String, _ arguments: [String], output: FileHandle?) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments
    process.standardOutput = output ?? FileHandle.nullDevice
    let errors = Pipe()
    process.standardError = errors
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
      let text = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
      throw NSError(domain: "Brim.logs", code: Int(process.terminationStatus),
                    userInfo: [NSLocalizedDescriptionKey: "\((path as NSString).lastPathComponent) failed. \(text)"])
    }
  }

  // MARK: Resets

  static func resetPanelSizes(defaults: UserDefaults = AppSettings.shared.defaults) {
    panelSizeKeys.forEach { defaults.removeObject(forKey: $0) }
    NotchShelfController.shared.settingsChanged()
    notify("Panel sizes reset", "The island and floating player are back to their default size.")
  }

  /// Removes every saved preference after a confirmation, then quits so nothing rewrites them.
  static func hardReset() {
    let alert = NSAlert()
    alert.alertStyle = .critical
    alert.messageText = L10n.tr("Reset all Brim settings?")
    alert.informativeText = L10n.tr("Every preference returns to its default and Brim quits. Your screenshots and clipboard history are not deleted. This can’t be undone.")
    alert.addButton(withTitle: L10n.tr("Reset and Quit"))
    alert.addButton(withTitle: L10n.tr("Cancel"))
    guard alert.runModal() == .alertFirstButtonReturn else { return }
    AppSettings.shared.defaults.removePersistentDomain(forName: domainName)
    AppSettings.shared.defaults.synchronize()
    log.notice("Hard reset performed")
    NSApp.terminate(nil)
  }

  // MARK: Feedback

  private static func notify(_ title: String, _ detail: String) {
    IslandFlashCenter.shared.show(title, symbol: "checkmark.circle.fill", tint: .green)
    log.notice("\(title, privacy: .public): \(detail, privacy: .public)")
  }

  private static func alert(_ title: String, _ detail: String) {
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = title
    alert.informativeText = detail
    alert.runModal()
  }
}
