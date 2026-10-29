import AppKit

/// The system switches behind the Command Center toggles. State reads are cheap preference lookups;
/// writes go through preferences (and a Finder restart where macOS needs one).
@MainActor
final class MacSwitches: ObservableObject {
  static let shared = MacSwitches()

  @Published private(set) var darkMode = false
  @Published private(set) var desktopIconsVisible = true
  @Published private(set) var hiddenFilesVisible = false
  @Published private(set) var lastError: String?

  func refresh() {
    darkMode = (UserDefaults.standard.string(forKey: "AppleInterfaceStyle") ?? "").lowercased() == "dark"
    let desktop = CFPreferencesCopyAppValue("CreateDesktop" as CFString, "com.apple.finder" as CFString)
    desktopIconsVisible = (desktop as? Bool) ?? true
    let hidden = CFPreferencesCopyAppValue("AppleShowAllFiles" as CFString, "com.apple.finder" as CFString)
    hiddenFilesVisible = (hidden as? Bool) ?? false
  }

  /// The tile flips at once; the AppleScript (which can take a second, or wait on an Automation
  /// prompt) runs off the main thread and the tile flips back if it fails.
  func toggleDarkMode() {
    let target = !darkMode
    darkMode = target
    Task.detached(priority: .userInitiated) {
      let failure = Self.setDarkMode(target)
      await MainActor.run {
        if let failure {
          self.darkMode = !target
          self.lastError = "Couldn't change appearance. Allow Brim to control System Events in Privacy & Security > Automation. \(failure)"
          IslandFlashCenter.shared.show(L10n.tr("Allow Automation to switch"), symbol: "exclamationmark.triangle.fill", tint: .orange)
        } else {
          self.lastError = nil
        }
      }
    }
  }

  /// Runs the appearance script; returns the error message, or nil when it worked.
  private nonisolated static func setDarkMode(_ dark: Bool) -> String? {
    let source = "tell application \"System Events\" to tell appearance preferences to set dark mode to \(dark)"
    var error: NSDictionary?
    NSAppleScript(source: source)?.executeAndReturnError(&error)
    guard let error else { return nil }
    return error[NSAppleScript.errorMessage] as? String ?? ""
  }

  func toggleDesktopIcons() {
    let next = !desktopIconsVisible
    writeFinder("CreateDesktop", next)
    desktopIconsVisible = next
  }

  func toggleHiddenFiles() {
    let next = !hiddenFilesVisible
    writeFinder("AppleShowAllFiles", next)
    hiddenFilesVisible = next
  }

  private func writeFinder(_ key: String, _ value: Bool) {
    CFPreferencesSetAppValue(key as CFString, value as CFBoolean, "com.apple.finder" as CFString)
    CFPreferencesAppSynchronize("com.apple.finder" as CFString)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
    process.arguments = ["Finder"]
    do {
      try process.run()
      lastError = nil
    } catch {
      lastError = "Couldn't restart Finder: \(error.localizedDescription)"
      IslandFlashCenter.shared.show(L10n.tr("Couldn't restart Finder"), symbol: "exclamationmark.triangle.fill", tint: .orange)
    }
  }

  func toggleIslandVisibility() {
    AppSettings.shared.notchShelfEnabled.toggle()
    NotchShelfController.shared.settingsChanged()
  }

  func toggleStayAwake() {
    let awake = KeepAwakeModel.shared
    awake.isActive ? awake.stop() : awake.start(minutes: nil)
  }
}
