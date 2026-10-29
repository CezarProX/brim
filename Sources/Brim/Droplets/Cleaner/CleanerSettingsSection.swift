import SwiftUI

/// Cleaner settings: on/off and a way to open it.
struct CleanerSettingsSection: View {
  @State private var enabled = AppSettings.shared.cleanerEnabled

  var body: some View {
    SettingsSection("Cleaner") {
      Toggle("Enable the app uninstaller and cache cleaner", isOn: $enabled)
        .onChange(of: enabled) { _, value in AppSettings.shared.cleanerEnabled = value }
      Text("Pick an app and see the files it leaves in your Library (Application Support, Caches, Preferences, Containers, Logs and more) with their sizes. Everything you confirm goes to the Trash, so it can be put back; nothing is deleted outright. Only your own ~/Library is searched, Apple’s apps and Brim are never offered, and the app must not be running.")
        .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      if enabled {
        HStack {
          Button("Open Cleaner") { CleanerController.shared.show() }
          Button("Clean caches…") { CleanerController.shared.show(mode: .caches) }
        }
        Text("Some apps in /Applications can only be removed with an administrator password; Cleaner reports those instead of forcing them.")
          .font(.footnote).foregroundStyle(.secondary)
      }
    }
  }
}
