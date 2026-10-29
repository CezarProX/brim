import SwiftUI

/// Meeting-control settings: the mute-every-microphone shortcut and the call apps' own keyboard shortcuts.
struct MeetingsSettingsSection: View {
  @State private var hotkey = AppSettings.shared.muteAllMicsHotkeyEnabled
  @State private var fallback = AppSettings.shared.meetingShortcutFallbackEnabled

  var body: some View {
    SettingsSection("Meetings") {
      Toggle("Press \u{2303}\u{2325}M anywhere to mute or unmute every microphone", isOn: $hotkey)
        .onChange(of: hotkey) { _, value in
          AppSettings.shared.muteAllMicsHotkeyEnabled = value
          MeetingHotkey.shared.register()
        }
      Toggle("Use the call app's own shortcuts when a button can't be pressed", isOn: $fallback)
        .onChange(of: fallback) { _, value in AppSettings.shared.meetingShortcutFallbackEnabled = value }
      Text("Zoom \u{21E7}\u{2318}A / \u{21E7}\u{2318}V / \u{21E7}\u{2318}S, Teams \u{21E7}\u{2318}M / \u{21E7}\u{2318}O / \u{21E7}\u{2318}E, Meet \u{2318}D / \u{2318}E (mic, camera, share). These need Accessibility, and Meet only works while the browser is in front. Leaving a call always asks first.")
        .font(.footnote).foregroundStyle(.secondary)
    }
  }
}
