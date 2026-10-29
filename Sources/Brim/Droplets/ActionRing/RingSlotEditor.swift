import AppKit
import SwiftUI

/// Edits one ring slot: label, icon, color and what it does.
struct RingSlotEditor: View {
  @State private var slot: RingSlot
  let onChange: (RingSlot?) -> Void
  @State private var shortcutNames: [String] = []

  init(slot: RingSlot, onChange: @escaping (RingSlot?) -> Void) {
    _slot = State(initialValue: slot)
    self.onChange = onChange
  }

  static let symbols = [
    "star.fill", "heart.fill", "bolt.fill", "flame.fill", "moon.fill", "sun.max.fill", "cloud.fill", "folder.fill",
    "doc.fill", "terminal.fill", "safari.fill", "envelope.fill", "message.fill", "phone.fill", "camera.fill",
    "photo.fill", "music.note", "play.fill", "gamecontroller.fill", "bell.fill", "lock.fill", "key.fill",
    "wand.and.stars", "paintbrush.fill", "hammer.fill", "wrench.fill", "cart.fill", "house.fill", "globe", "link",
  ]

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Image(systemName: slot.symbol).foregroundStyle(slot.color).frame(width: 22)
        TextField("Title", text: $slot.title).textFieldStyle(.roundedBorder)
        ColorPicker("", selection: colorBinding).labelsHidden()
        Button(role: .destructive) { onChange(nil) } label: { Image(systemName: "trash") }.help("Clear this slot")
      }
      symbolStrip
      Picker("Does", selection: kindBinding) {
        ForEach(RingActionKind.allCases) { Text($0.title).tag($0) }
      }
      argumentEditor
    }
    .padding(12)
    .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
    .onChange(of: slot) { _, value in onChange(value) }
  }

  private var symbolStrip: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 4) {
        ForEach(Self.symbols, id: \.self) { name in
          Button { slot.symbol = name } label: {
            Image(systemName: name).frame(width: 26, height: 26)
              .background(slot.symbol == name ? Color.accentColor.opacity(0.3) : .clear, in: RoundedRectangle(cornerRadius: 6))
          }
          .buttonStyle(.plain)
        }
        TextField("SF Symbol", text: $slot.symbol).textFieldStyle(.roundedBorder).frame(width: 130)
      }
    }
  }

  @ViewBuilder private var argumentEditor: some View {
    switch slot.kind {
    case .builtIn:
      Picker("Action", selection: argumentBinding) {
        ForEach(RingBuiltIn.allCases) { Text(RingPresets.preset(kind: .builtIn, argument: $0.rawValue).title).tag($0.rawValue) }
      }
    case .media:
      Picker("Control", selection: argumentBinding) {
        ForEach(RingMedia.allCases) { Text(RingPresets.preset(kind: .media, argument: $0.rawValue).title).tag($0.rawValue) }
      }
    case .toggle:
      Picker("Toggle", selection: argumentBinding) {
        ForEach(RingToggle.allCases) { Text(RingPresets.preset(kind: .toggle, argument: $0.rawValue).title).tag($0.rawValue) }
      }
    case .openApp:
      HStack {
        Text(slot.argument.isEmpty ? "No app chosen" : slot.argument).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        Spacer()
        Button("Choose…") { chooseApp() }
      }
    case .openURL:
      TextField("https://…", text: argumentBinding).textFieldStyle(.roundedBorder)
    case .shortcut:
      HStack {
        TextField("Shortcut name", text: argumentBinding).textFieldStyle(.roundedBorder)
        if !shortcutNames.isEmpty {
          Menu("Pick") { ForEach(shortcutNames, id: \.self) { name in Button(name) { setArgument(name) } } }.fixedSize()
        }
      }
      .task { await loadShortcuts() }
    case .keystroke:
      HStack {
        ShortcutField(display: RingKeystroke(slot.argument)?.display ?? "") { code, mods, label in
          setArgument(RingKeystroke(keyCode: code, modifiers: mods, label: label).argument)
        }
        .frame(width: 140, height: 24)
        Text("Sent to the front app. Needs Accessibility access.").font(.caption).foregroundStyle(.secondary)
      }
    }
  }

  // MARK: Bindings

  private var kindBinding: Binding<RingActionKind> {
    Binding(
      get: { slot.kind },
      set: { kind in
        let argument = Self.defaultArgument(kind)
        let preset = RingPresets.preset(kind: kind, argument: argument)
        slot.kind = kind
        slot.argument = argument
        slot.title = preset.title
        slot.symbol = preset.symbol
        slot.colorHex = preset.colorHex
      })
  }

  private var argumentBinding: Binding<String> {
    Binding(get: { slot.argument }, set: { setArgument($0) })
  }

  private var colorBinding: Binding<Color> {
    Binding(
      get: { slot.color },
      set: { color in
        if let hex = NSColor(color).usingColorSpace(.sRGB).flatMap({ ClipboardEntry.hex($0) }) { slot.colorHex = hex }
      })
  }

  /// Changing the argument refreshes the title/icon only while they still match the old preset.
  private func setArgument(_ argument: String) {
    let old = RingPresets.preset(kind: slot.kind, argument: slot.argument)
    let new = RingPresets.preset(kind: slot.kind, argument: argument)
    if slot.title == old.title { slot.title = new.title }
    if slot.symbol == old.symbol { slot.symbol = new.symbol }
    if slot.colorHex == old.colorHex { slot.colorHex = new.colorHex }
    slot.argument = argument
  }

  static func defaultArgument(_ kind: RingActionKind) -> String {
    switch kind {
    case .builtIn: RingBuiltIn.capture.rawValue
    case .media: RingMedia.playPause.rawValue
    case .toggle: RingToggle.keepAwake.rawValue
    case .openURL: "https://"
    case .openApp, .shortcut, .keystroke: ""
    }
  }

  private func chooseApp() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.application]
    panel.directoryURL = URL(fileURLWithPath: "/Applications")
    if panel.runModal() == .OK, let url = panel.url { setArgument(url.path) }
  }

  private func loadShortcuts() async {
    guard shortcutNames.isEmpty, let result = await DropletProcess.run("/usr/bin/shortcuts", ["list"], timeout: 8),
      result.status == 0
    else { return }
    shortcutNames = result.output.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
  }
}
