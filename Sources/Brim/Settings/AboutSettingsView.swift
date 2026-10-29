import AppKit
import SwiftUI

/// About: version, replay the tour, and the settings utilities.
struct AboutSettingsView: View {
  var body: some View {
    Group {
      Section {
        LabeledContent {
          Text("\(SettingsUtilities.appVersion) (\(SettingsUtilities.buildNumber))").monospacedDigit()
        } label: {
          Label {
            Text("Brim")
          } icon: {
            Image(nsImage: AppIconRenderer.image(for: AppSettings.shared.appIconVariant, size: 64)).resizable()
              .frame(width: 22, height: 22)
          }
        }
      } header: {
        Text("Version")
      }
      Section {
        SettingsButtonRow(
          "Introduction", subtitle: "Walk through the notch, the Command Center and the permissions again.",
          button: "Replay introduction"
        ) { OnboardingWindowController.shared.show() }
        IslandTourSettingsRow()
      } header: {
        Text("Introduction")
      }
      UpdatesSettingsSection()
      Section {
        SettingsButtonRow(
          "Settings file", subtitle: "A JSON file of your preferences. Tokens, caches and macOS-owned keys are left out.",
          button: "Export settings…"
        ) { SettingsUtilities.exportSettings() }
        SettingsButtonRow("Restore from a file", button: "Import settings…") { SettingsUtilities.importSettings() }
      } header: {
        Text("Backup")
      }
      Section {
        SettingsButtonRow(
          "Logs", subtitle: "The last hour of Brim’s system log, zipped onto your Desktop. They stay on your Mac until you send them.",
          button: "Export logs…"
        ) { SettingsUtilities.exportLogs() }
        SettingsButtonRow(
          "Island and player size", subtitle: "Put the island and floating player back to their default size.",
          button: "Reset panel size"
        ) { SettingsUtilities.resetPanelSizes() }
        SettingsButtonRow(
          "Hard reset", subtitle: "Erases every Brim preference and quits.", button: "Hard reset…", role: .destructive
        ) { SettingsUtilities.hardReset() }
      } header: {
        Text("Troubleshooting")
      }
    }
  }
}
