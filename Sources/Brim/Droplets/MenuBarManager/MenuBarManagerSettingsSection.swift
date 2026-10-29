import SwiftUI

/// Menu Bar Manager settings. Off by default.
struct MenuBarManagerSettingsSection: View {
  @State private var enabled = AppSettings.shared.menuBarManagerEnabled
  @State private var shortcut = AppSettings.shared.menuBarManagerShortcut
  @State private var autoRehide = AppSettings.shared.menuBarManagerAutoRehide
  @State private var seconds = Double(AppSettings.shared.menuBarManagerRehideSeconds)
  @State private var startCollapsed = AppSettings.shared.menuBarManagerStartCollapsed
  @ObservedObject private var manager = MenuBarManagerController.shared

  var body: some View {
    SettingsSection("Menu Bar Manager") {
      Toggle("Hide menu bar icons behind an arrow", isOn: $enabled)
        .onChange(of: enabled) { _, value in
          AppSettings.shared.menuBarManagerEnabled = value
          MenuBarManagerController.shared.start()
        }
      Text("Adds a divider and an arrow to the menu bar. Hold ⌘ and drag icons to the left of the divider; clicking the arrow hides them and shows them again. This is a best-effort technique: macOS has no official way to hide other apps’ icons, so it only affects what sits left of the divider.")
        .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      if enabled {
        DropletShortcutField(title: "Show / hide shortcut", shortcut: $shortcut)
          .onChange(of: shortcut) { _, value in
            AppSettings.shared.menuBarManagerShortcut = value
            MenuBarManagerController.shared.start()
          }
        Toggle("Hide icons again automatically", isOn: $autoRehide)
          .onChange(of: autoRehide) { _, v in AppSettings.shared.menuBarManagerAutoRehide = v }
        if autoRehide {
          HStack {
            Text("After")
            Slider(value: $seconds, in: 2...60, step: 1).frame(maxWidth: 220)
            Text("\(Int(seconds)) s").monospacedDigit().foregroundStyle(.secondary)
          }
          .onChange(of: seconds) { _, v in AppSettings.shared.menuBarManagerRehideSeconds = Int(v) }
        }
        Toggle("Hide icons when Brim starts", isOn: $startCollapsed)
          .onChange(of: startCollapsed) { _, v in AppSettings.shared.menuBarManagerStartCollapsed = v }
        if let notice = manager.lastNotice { Text(notice).font(.caption).foregroundStyle(.orange) }
        Text("Safety: icons are only hidden while the divider is left of the arrow, so the arrow can never be pushed off the bar. On a Mac with a notch, macOS may hide icons by itself when the bar is crowded.")
          .font(.footnote).foregroundStyle(.secondary)
      }
    }
  }
}
