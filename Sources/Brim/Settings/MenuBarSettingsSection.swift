import SwiftUI

/// Menu bar: click behavior, the Command Center, live status and the optional readouts.
struct MenuBarSettingsSection: View {
  @State private var style = AppSettings.shared.menuBarClickStyle
  @State private var startPage = AppSettings.shared.commandCenterStartPage
  @State private var closesAfterAction = AppSettings.shared.commandCenterClosesAfterAction
  @State private var liveStatus = AppSettings.shared.menuBarLiveStatus
  @State private var readout = AppSettings.shared.menuBarStatsReadout
  @State private var showsSong = AppSettings.shared.menuBarShowsSong
  @State private var playerMenuBar = AppSettings.shared.liquidPlayerMenuBarMode

  private var settings: AppSettings { .shared }

  var body: some View {
    Group {
        SettingsSection(
          "Menu bar icon",
          footer: "Command Center shows pages of tiles. The short menu is the classic list. Right-click the icon for the short menu either way."
        ) {
          Picker("Clicking the icon opens", selection: $style) {
            ForEach(MenuBarClickStyle.allCases) { Text($0.title).tag($0) }
          }
          .onChange(of: style) { _, value in settings.menuBarClickStyle = value }
        }
        if style == .commandCenter { commandCenter }
        section("Live status") {
          Toggle(isOn: $liveStatus) {
            Text("Icon shows what’s happening")
            Text("A waveform while music plays, the time left on a timer, a red dot while recording, and a sparkle while a coding agent works.")
          }
          .onChange(of: liveStatus) { _, v in settings.menuBarLiveStatus = v }
          Picker("Readout beside the icon", selection: $readout) {
            ForEach(MenuBarStatsReadout.allCases) { Text($0.title).tag($0) }
          }
          .onChange(of: readout) { _, v in settings.menuBarStatsReadout = v }
          Toggle("Song title beside the icon", isOn: $showsSong).onChange(of: showsSong) { _, v in settings.menuBarShowsSong = v }
            .disabled(playerMenuBar)
          if playerMenuBar {
            Text("The floating player’s own menu-bar item already shows the song (Media > Floating player).").caption()
          }
        }
    }
    .onAppear { playerMenuBar = settings.liquidPlayerMenuBarMode }
  }

  private var commandCenter: some View {
    SettingsSection("Command Center", footer: "Add, remove, resize and drag tiles to reorder them.") {
      Picker("Opens on", selection: $startPage) {
        ForEach(CommandCenterStartPage.allCases) { Text($0.title).tag($0) }
      }
      .onChange(of: startPage) { _, v in settings.commandCenterStartPage = v }
      .settingsAnchor("menubar.commandCenter")
      Toggle("Close after an action", isOn: $closesAfterAction).onChange(of: closesAfterAction) { _, v in settings.commandCenterClosesAfterAction = v }
      LabeledContent("Tiles") {
        HStack {
          Menu("Layout preset") {
            ForEach(CommandCenterLayout.presets) { preset in
              Button(preset.title) { CommandCenterStore.shared.apply(preset) }
            }
          }
          .fixedSize()
          Button("Edit Command Center…") { MenuBarController.shared.openCommandCenterForEditing() }
        }
      }
    }
  }

  private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
    SettingsSection(title) { content() }
  }
}

private extension Text {
  func caption() -> some View { font(.footnote).foregroundStyle(.secondary) }
}
