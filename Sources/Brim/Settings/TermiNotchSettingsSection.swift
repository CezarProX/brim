// TermiNotchSettingsSection.swift
// Brim

import SwiftUI

struct TermiNotchSettingsSection: View {
  @State private var enabled = AppSettings.shared.termiNotchEnabled
  @State private var shortcut = AppSettings.shared.termiNotchShortcut
  @State private var fontSize = AppSettings.shared.termiNotchFontSize
  @State private var external = AppSettings.shared.termiNotchExternalApp
  @State private var inherit = AppSettings.shared.termiNotchInheritFolder

  var body: some View {
    SettingsSection("Termi-Notch") {
      Toggle("Enable the terminal droplet", isOn: $enabled)
        .onChange(of: enabled) { _, value in
          AppSettings.shared.termiNotchEnabled = value
          TermiNotchController.shared.settingsChanged()
        }
      Text("A quick terminal that runs your login shell. Brim never types or runs a command for you; only your own keystrokes reach the shell.")
        .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      if enabled {
        DropletShortcutField(title: "Drop down shortcut", shortcut: $shortcut)
          .onChange(of: shortcut) { _, value in
            AppSettings.shared.termiNotchShortcut = value
            TermiNotchController.shared.settingsChanged()
          }
        Stepper("Text size \(fontSize) pt", value: $fontSize, in: 9...18)
          .onChange(of: fontSize) { _, value in
            AppSettings.shared.termiNotchFontSize = value
            TermiNotchModel.shared.objectWillChange.send()
          }
        Toggle("New tabs start in the current folder", isOn: $inherit)
          .onChange(of: inherit) { _, value in AppSettings.shared.termiNotchInheritFolder = value }
        Picker("Hand off to", selection: $external) {
          ForEach(ExternalTerminal.allCases) { Text($0.title).tag($0.rawValue) }
        }
        .onChange(of: external) { _, value in AppSettings.shared.termiNotchExternalApp = value }
      }
    }
  }
}
