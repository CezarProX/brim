import Foundation
import SwiftUI

/// What a ring slot does. The `argument` of a slot is interpreted according to its kind.
enum RingActionKind: String, Codable, CaseIterable, Identifiable, Sendable {
  case builtIn, media, toggle, openApp, openURL, shortcut, keystroke
  var id: String { rawValue }
  var title: String {
    switch self {
    case .builtIn: "Brim action"
    case .media: "Media control"
    case .toggle: "Toggle"
    case .openApp: "Open app"
    case .openURL: "Open URL"
    case .shortcut: "Run Shortcut"
    case .keystroke: "Keyboard shortcut"
    }
  }
}

enum RingBuiltIn: String, Codable, CaseIterable, Identifiable, Sendable {
  case capture, grabText, colorPicker, voiceMemo, emojiPicker, clipboard, settings
  var id: String { rawValue }
}

enum RingMedia: String, Codable, CaseIterable, Identifiable, Sendable {
  case playPause, next, previous, volumeUp, volumeDown, mute
  var id: String { rawValue }
}

enum RingToggle: String, Codable, CaseIterable, Identifiable, Sendable {
  case keepAwake, darkMode
  var id: String { rawValue }
}

/// Title, icon and color a freshly chosen action starts with (the user may override each).
struct RingPreset: Equatable, Sendable {
  let title: String
  let symbol: String
  let colorHex: String
}

enum RingPresets {
  static func preset(kind: RingActionKind, argument: String) -> RingPreset {
    switch kind {
    case .builtIn: builtIn(RingBuiltIn(rawValue: argument))
    case .media: media(RingMedia(rawValue: argument))
    case .toggle: toggle(RingToggle(rawValue: argument))
    case .openApp:
      RingPreset(title: appName(argument), symbol: "app.fill", colorHex: "#5E9CFF")
    case .openURL: RingPreset(title: urlLabel(argument), symbol: "link", colorHex: "#4FD1C5")
    case .shortcut: RingPreset(title: argument.isEmpty ? "Shortcut" : argument, symbol: "square.stack.3d.up.fill", colorHex: "#FF6B9D")
    case .keystroke:
      RingPreset(title: RingKeystroke(argument)?.display ?? "Keys", symbol: "command", colorHex: "#B38CFF")
    }
  }

  private static func builtIn(_ value: RingBuiltIn?) -> RingPreset {
    switch value {
    case .capture: RingPreset(title: "Capture", symbol: "plus.viewfinder", colorHex: "#4C8DFF")
    case .grabText: RingPreset(title: "Grab Text", symbol: "text.viewfinder", colorHex: "#2EC4B6")
    case .colorPicker: RingPreset(title: "Pick Color", symbol: "eyedropper", colorHex: "#FF5FA2")
    case .voiceMemo: RingPreset(title: "Voice Memo", symbol: "waveform", colorHex: "#FF453A")
    case .emojiPicker: RingPreset(title: "Emoji", symbol: "face.smiling", colorHex: "#FF9F0A")
    case .clipboard: RingPreset(title: "Clipboard", symbol: "doc.on.clipboard", colorHex: "#64D2FF")
    case .settings: RingPreset(title: "Settings", symbol: "gearshape.fill", colorHex: "#98989D")
    case nil: RingPreset(title: "Action", symbol: "questionmark", colorHex: "#98989D")
    }
  }

  private static func media(_ value: RingMedia?) -> RingPreset {
    switch value {
    case .playPause: RingPreset(title: "Play/Pause", symbol: "playpause.fill", colorHex: "#FFFFFF")
    case .next: RingPreset(title: "Next", symbol: "forward.fill", colorHex: "#FFFFFF")
    case .previous: RingPreset(title: "Previous", symbol: "backward.fill", colorHex: "#FFFFFF")
    case .volumeUp: RingPreset(title: "Volume Up", symbol: "speaker.plus.fill", colorHex: "#FF5FA2")
    case .volumeDown: RingPreset(title: "Volume Down", symbol: "speaker.minus.fill", colorHex: "#FF5FA2")
    case .mute: RingPreset(title: "Mute", symbol: "speaker.slash.fill", colorHex: "#FF5FA2")
    case nil: RingPreset(title: "Media", symbol: "music.note", colorHex: "#FF5FA2")
    }
  }

  private static func toggle(_ value: RingToggle?) -> RingPreset {
    switch value {
    case .keepAwake: RingPreset(title: "Keep Awake", symbol: "cup.and.saucer.fill", colorHex: "#FFD60A")
    case .darkMode: RingPreset(title: "Dark Mode", symbol: "circle.lefthalf.filled", colorHex: "#BF5AF2")
    case nil: RingPreset(title: "Toggle", symbol: "switch.2", colorHex: "#98989D")
    }
  }

  static func appName(_ path: String) -> String {
    guard !path.isEmpty else { return "App" }
    return URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
  }

  static func urlLabel(_ text: String) -> String {
    URL(string: text)?.host ?? (text.isEmpty ? "Link" : String(text.prefix(14)))
  }
}

/// A keystroke posted by a slot. Stored as "keyCode|carbonModifiers|label".
struct RingKeystroke: Equatable, Sendable {
  let keyCode: Int
  let modifiers: Int
  let label: String

  init(keyCode: Int, modifiers: Int, label: String) {
    self.keyCode = keyCode
    self.modifiers = modifiers
    self.label = label
  }

  init?(_ argument: String) {
    let parts = argument.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false)
    guard parts.count == 3, let code = Int(parts[0]), let mods = Int(parts[1]), (0...127).contains(code)
    else { return nil }
    self.init(keyCode: code, modifiers: mods, label: String(parts[2]))
  }

  var argument: String { "\(keyCode)|\(modifiers)|\(label)" }
  var display: String { HotkeyFormat.modifierSymbols(modifiers) + label }
}

/// One ring position. A slot can be left empty by storing `nil` in the ring.
struct RingSlot: Codable, Identifiable, Equatable, Sendable {
  var id: UUID
  var title: String
  var symbol: String
  var colorHex: String
  var kind: RingActionKind
  var argument: String

  init(id: UUID = UUID(), title: String, symbol: String, colorHex: String, kind: RingActionKind, argument: String) {
    self.id = id
    self.title = title
    self.symbol = symbol
    self.colorHex = colorHex
    self.kind = kind
    self.argument = argument
  }

  /// A slot filled from the preset for an action.
  init(kind: RingActionKind, argument: String) {
    let preset = RingPresets.preset(kind: kind, argument: argument)
    self.init(title: preset.title, symbol: preset.symbol, colorHex: preset.colorHex, kind: kind, argument: argument)
  }

  var color: Color { Color(hex: colorHex) ?? .white }
}

/// One ring of up to eight slots, clockwise from twelve o'clock.
struct RingPage: Codable, Identifiable, Equatable, Sendable {
  static let slotCount = 8
  var id: UUID
  var name: String
  var slots: [RingSlot?]

  init(id: UUID = UUID(), name: String, slots: [RingSlot?] = []) {
    self.id = id
    self.name = name
    self.slots = Array((slots + Array(repeating: nil, count: Self.slotCount)).prefix(Self.slotCount))
  }
}

extension Color {
  /// "#RRGGBB" to a color; nil when malformed.
  init?(hex: String) {
    var text = hex.trimmingCharacters(in: .whitespaces)
    if text.hasPrefix("#") { text.removeFirst() }
    guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
    self.init(
      .sRGB, red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255,
      blue: Double(value & 0xFF) / 255, opacity: 1)
  }
}
