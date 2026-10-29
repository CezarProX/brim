import SwiftUI

/// Emoji Picker settings: on/off, shortcut, columns, default skin tone.
struct EmojiSettingsSection: View {
  @State private var enabled = AppSettings.shared.emojiPickerEnabled
  @State private var label = AppSettings.shared.emojiHotkeyLabel
  @State private var modifiers = AppSettings.shared.emojiHotkeyModifiers
  @State private var columns = Double(AppSettings.shared.emojiColumns)
  @State private var tone = EmojiSkinTone(rawValue: AppSettings.shared.emojiSkinToneRaw) ?? .none

  var body: some View {
    SettingsSection("Emoji Picker") {
      Toggle("Open an emoji picker with a shortcut", isOn: $enabled)
        .onChange(of: enabled) { _, value in
          AppSettings.shared.emojiPickerEnabled = value
          EmojiPickerController.shared.start()
        }
      if enabled {
        HStack {
          Text("Shortcut")
          Spacer()
          ShortcutField(display: HotkeyFormat.modifierSymbols(modifiers) + label) { code, mods, text in
            AppSettings.shared.emojiHotkeyCode = code
            AppSettings.shared.emojiHotkeyModifiers = mods
            AppSettings.shared.emojiHotkeyLabel = text
            modifiers = mods
            label = text
            EmojiPickerController.shared.start()
          }
          .frame(width: 140, height: 24)
        }
        HStack {
          Text("Columns")
          Slider(value: $columns, in: 5...12, step: 1).frame(maxWidth: 220)
          Text("\(Int(columns))").monospacedDigit().foregroundStyle(.secondary)
        }
        .onChange(of: columns) { _, value in AppSettings.shared.emojiColumns = Int(value) }
        Picker("Skin tone", selection: $tone) {
          ForEach(EmojiSkinTone.allCases) { Text("\($0.swatch)  \($0.title)").tag($0) }
        }
        .onChange(of: tone) { _, value in AppSettings.shared.emojiSkinToneRaw = value.rawValue }
        Text("Type to search, use the arrow keys and Return. The emoji is pasted into the app you were in, and your clipboard is put back afterwards. Pasting needs Accessibility access; without it the emoji is copied for you to paste.")
          .font(.footnote).foregroundStyle(.secondary)
      }
    }
  }
}
