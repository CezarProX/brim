// CaptureSettingsSections.swift
// Brim
//
// Capture & Recording: what happens right after a capture, then the floating thumbnail.

import SwiftUI

struct CaptureSettingsSections: View {
  @State private var showNotifications = AppSettings.shared.showNotifications
  @State private var playSound = AppSettings.shared.playSound
  @State private var closeAfterCopy = AppSettings.shared.closeAfterCopy
  @State private var closeAfterSave = AppSettings.shared.closeAfterSave

  var body: some View {
    Section {
      SettingsButtonRow(
        "Screenshot", subtitle: "Start a capture here or with your keyboard shortcut. macOS checks screen access when you capture.",
        button: "Take Screenshot"
      ) { CaptureCoordinator.shared.startCapture() }
    }
    Section("After a capture") {
      Toggle("Show notifications", isOn: $showNotifications)
        .onChange(of: showNotifications) { _, value in AppSettings.shared.showNotifications = value }
      Toggle("Play sound after capture", isOn: $playSound)
        .onChange(of: playSound) { _, value in AppSettings.shared.playSound = value }
      Toggle("Auto-close after copy", isOn: $closeAfterCopy)
        .onChange(of: closeAfterCopy) { _, value in AppSettings.shared.closeAfterCopy = value }
      Toggle("Auto-close after save", isOn: $closeAfterSave)
        .onChange(of: closeAfterSave) { _, value in AppSettings.shared.closeAfterSave = value }
    }
    CaptureThumbnailSettingsSection()
  }
}
