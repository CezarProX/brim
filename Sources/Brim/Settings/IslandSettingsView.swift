// IslandSettingsView.swift
// Brim
//
// One place for the island's look, live activities, skins and shelf behavior.

import SwiftUI

struct IslandSettingsView: View {
  @State private var system = AppSettings.shared.systemActivityEnabled
  @State private var power = AppSettings.shared.powerFlashesEnabled
  @State private var privacy = AppSettings.shared.privacyFlashesEnabled
  @State private var downloads = AppSettings.shared.downloadFlashesEnabled
  @State private var browser = AppSettings.shared.browserSkinEnabled
  @State private var coding = AppSettings.shared.codingAgentSkinEnabled
  @State private var workspace = AppSettings.shared.workspaceActivityEnabled
  @State private var basket = AppSettings.shared.basketEnabled

  var body: some View {
    Group {
      Section {
        row("Caps Lock", "Flashes when Caps Lock turns on or off", isOn: $system) {
          WorkspaceActivityModel.shared.setSystemEnabled($0)
        }
        row("Charging & battery", "Plugged in, unplugged and low battery", isOn: $power) {
          AppSettings.shared.powerFlashesEnabled = $0
        }
        row("Camera & microphone", "Flashes when either starts or stops", isOn: $privacy) {
          AppSettings.shared.privacyFlashesEnabled = $0
        }
        row("Downloads", "macOS will ask to allow the Downloads folder", isOn: $downloads) {
          AppSettings.shared.downloadFlashesEnabled = $0
        }
        row("Browser", "Tab, back, forward and new tab for the front browser", isOn: $browser) { value in
          AppSettings.shared.browserSkinEnabled = value
          value ? BrowserSkinModel.shared.start() : BrowserSkinModel.shared.stop()
        }
        row("Claude Code & Codex", "Session state and tokens from local transcripts", isOn: $coding) { value in
          AppSettings.shared.codingAgentSkinEnabled = value
          value ? CodingAgentModel.shared.start() : CodingAgentModel.shared.stop()
        }
        row("Current app", "Shows the front app when nothing else is live", isOn: $workspace) {
          WorkspaceActivityModel.shared.setWorkspaceEnabled($0)
        }
      }
      SettingsSection("Shelf", footer: "Drop files on the notch to keep them on the Shelf. Press ⌥⌘R anywhere for the Ring.") {
        Toggle("Shake while dragging files to open the Basket", isOn: $basket)
          .onChange(of: basket) { _, value in
            AppSettings.shared.basketEnabled = value
            FloatingBasketController.shared.settingsChanged()
          }
      }
    }
  }

  /// A switch with a one-line explanation under its title.
  private func row(
    _ title: LocalizedStringKey, _ detail: LocalizedStringKey, isOn: Binding<Bool>, apply: @escaping (Bool) -> Void
  ) -> some View {
    Toggle(isOn: isOn) {
      Text(title)
      Text(detail)
    }
    .onChange(of: isOn.wrappedValue) { _, value in apply(value) }
  }
}
