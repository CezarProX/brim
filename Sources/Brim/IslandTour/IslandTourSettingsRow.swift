import SwiftUI

/// "Take the Island Tour" for Settings (General and About). With the island off it explains that
/// instead of starting.
struct IslandTourSettingsRow: View {
  /// Whether the island (notch shelf) is on; General passes its live toggle.
  var islandEnabled: Bool = AppSettings.shared.notchShelfEnabled

  var body: some View {
    SettingsButtonRow(
      "Island Tour",
      subtitle: islandEnabled
        ? "A short guided tour on the real island: open it, then find Home, Clipboard, Music and Widgets."
        : "Turn on “Enable Brim at the notch” to take the Island Tour.",
      button: "Take the Tour"
    ) { IslandTourController.shared.start() }
    .disabled(!islandEnabled)
  }
}
