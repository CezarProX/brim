import SwiftUI

/// Settings > General > "Floating thumbnail": on/off, corner and how long an untouched card stays.
struct CaptureThumbnailSettingsSection: View {
  @State private var enabled = AppSettings.shared.captureThumbnailEnabled
  @State private var corner = AppSettings.shared.captureThumbnailCorner
  @State private var autoClose = AppSettings.shared.captureThumbnailAutoClose

  var body: some View {
    SettingsSection(
      "Floating thumbnail",
      footer: "Hover to copy, save, edit or copy its text. Drag it into any app, or flick it toward the edge to dismiss. Pinned or hovered thumbnails stay. Captures still go to the island as before."
    ) {
      Toggle("Show a thumbnail after each capture", isOn: $enabled)
        .onChange(of: enabled) { _, value in
          AppSettings.shared.captureThumbnailEnabled = value
          CaptureThumbnailCenter.shared.settingsChanged()
        }
      Picker("Corner", selection: $corner) {
        ForEach(ThumbnailCorner.allCases) { corner in Text(verbatim: corner.title).tag(corner) }
      }
      .disabled(!enabled)
      .onChange(of: corner) { _, value in
        AppSettings.shared.captureThumbnailCorner = value
        CaptureThumbnailCenter.shared.settingsChanged()
      }
      Picker("Close automatically", selection: $autoClose) {
        ForEach(AppSettings.captureThumbnailDelayChoices, id: \.self) { seconds in
          Text(verbatim: Self.delayTitle(seconds)).tag(seconds)
        }
      }
      .disabled(!enabled)
      .onChange(of: autoClose) { _, value in AppSettings.shared.captureThumbnailAutoClose = value }
    }
  }

  static func delayTitle(_ seconds: TimeInterval) -> String {
    seconds <= 0 ? L10n.tr("Never") : L10n.tr("After %lld seconds", Int(seconds))
  }
}
