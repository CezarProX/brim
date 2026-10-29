import AppKit
import SwiftUI

/// Settings for the Droplets package: Action Ring, Emoji Picker, LocalSend, MCP, Xcode Builds,
/// Stay Awake, Termi-Notch, Teleprompter, Text Capture, DropClip and Finder Services.
/// Sections for the Droplets pane's grouped Form.
struct DropletsSettingsSection: View {
  var body: some View {
    Group {
      RingSettingsSection()
      EmojiSettingsSection()
      LocalSendSettingsSection()
      MCPSettingsSection()
      XcodeBuildsSettingsSection()
      StayAwakeSettingsSection()
      TermiNotchSettingsSection()
      TeleprompterSettingsSection()
      TextCaptureSettingsSection()
      DropClipSettingsSection()
      ThunderstormSettingsSection()
      CleanerSettingsSection()
      MenuBarManagerSettingsSection()
      FinderServicesSettingsSection()
    }
  }
}

/// Where the Finder Services live and how to turn them on.
struct FinderServicesSettingsSection: View {
  var body: some View {
    SettingsSection(
      "Finder Services",
      footer: "Select files in Finder, then choose Finder > Services > “Add to Brim Tray” or “Transform with Brim” (also in the right-click menu under Quick Actions or Services). If they don’t appear, enable them in System Settings > Keyboard > Keyboard Shortcuts > Services > Files and Folders."
    ) {
      LabeledContent("Services") {
        Button("Open Keyboard Shortcuts…") {
          if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
            NSWorkspace.shared.open(url)
          }
        }
      }
    }
  }
}
