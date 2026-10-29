// TeleprompterSettingsSection.swift
// Brim

import SwiftUI

struct TeleprompterSettingsSection: View {
  @State private var enabled = AppSettings.shared.teleprompterEnabled
  @State private var shortcut = AppSettings.shared.teleprompterShortcut
  @State private var speed = AppSettings.shared.teleprompterSpeed
  @State private var fontSize = AppSettings.shared.teleprompterFontSize
  @State private var mirrored = AppSettings.shared.teleprompterMirrored
  @State private var hoverPause = AppSettings.shared.teleprompterHoverPause
  @State private var hidden = AppSettings.shared.teleprompterHiddenFromCapture

  var body: some View {
    SettingsSection("Teleprompter") {
      Toggle("Enable the teleprompter droplet", isOn: $enabled)
        .onChange(of: enabled) { _, value in
          AppSettings.shared.teleprompterEnabled = value
          TeleprompterController.shared.settingsChanged()
        }
      Text("Scrolls your script right under the camera and stays above fullscreen apps while it is showing. Space plays or pauses, the arrow keys change the speed, and resting the pointer on it pauses.")
        .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      if enabled {
        DropletShortcutField(title: "Show / hide shortcut", shortcut: $shortcut)
          .onChange(of: shortcut) { _, value in
            AppSettings.shared.teleprompterShortcut = value
            TeleprompterController.shared.settingsChanged()
          }
        Stepper("Speed \(speed)", value: $speed, in: TeleprompterMath.levels)
          .onChange(of: speed) { _, value in TeleprompterModel.shared.setSpeed(value) }
        Stepper("Text size \(fontSize) pt", value: $fontSize, in: 16...48, step: 2)
          .onChange(of: fontSize) { _, value in TeleprompterModel.shared.setFontSize(value) }
        Toggle("Mirror the text (for a beam-splitter prompter)", isOn: $mirrored)
          .onChange(of: mirrored) { _, value in TeleprompterModel.shared.setMirrored(value) }
        Toggle("Pause while the pointer is over it", isOn: $hoverPause)
          .onChange(of: hoverPause) { _, value in AppSettings.shared.teleprompterHoverPause = value }
        Toggle("Hide from screen recordings and sharing", isOn: $hidden)
          .onChange(of: hidden) { _, value in
            AppSettings.shared.teleprompterHiddenFromCapture = value
            TeleprompterController.shared.settingsChanged()
          }
      }
    }
  }
}
