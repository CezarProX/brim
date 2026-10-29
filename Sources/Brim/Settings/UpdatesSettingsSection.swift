// UpdatesSettingsSection.swift
// Brim

import SwiftUI

/// Official signed releases install through Sparkle; automatic checks only announce availability.
struct UpdatesSettingsSection: View {
  @ObservedObject private var updater = AppUpdater.shared
  @State private var auto = AppSettings.shared.updateAutoCheck

  var body: some View {
    SettingsSection(
      "Updates",
      footer: "Signed updates come from Brim’s GitHub Releases. Install and relaunch from the island without downloading the app again. Background checks never install updates automatically."
    ) {
      Toggle("Check once a day in the background", isOn: $auto)
        .onChange(of: auto) { _, value in
          AppSettings.shared.updateAutoCheck = value
          updater.startAutoCheck()
        }
      LabeledContent {
        Button(action: updater.checkInteractively) {
          Text(updater.availableVersion.map { L10n.tr("Update to %@", $0) }
               ?? L10n.tr(updater.isChecking ? "Checking for Updates…" : "Check for Updates"))
        }
        .disabled(updater.isChecking)
      } label: {
        Text("Software update")
        if let last = AppSettings.shared.updateLastCheck {
          Text("Last checked \(last.formatted(.relative(presentation: .named)))")
        }
      }
      if let error = updater.lastError {
        Text(error).font(.caption).foregroundStyle(.orange)
      }
    }
  }
}
