import AppKit

/// The hardware keys that macOS delivers as `NX_SYSDEFINED` auxiliary-control events.
enum MediaKey: Int, Equatable {
  case soundUp = 0
  case soundDown = 1
  case brightnessUp = 2
  case brightnessDown = 3
  case mute = 7
  case illuminationUp = 21
  case illuminationDown = 22

  enum Kind: Equatable { case volume, brightness, keyboard }

  var kind: Kind {
    switch self {
    case .soundUp, .soundDown, .mute: return .volume
    case .brightnessUp, .brightnessDown: return .brightness
    case .illuminationUp, .illuminationDown: return .keyboard
    }
  }

  /// +1, -1 for the step keys; 0 for mute.
  var direction: Int {
    switch self {
    case .soundUp, .brightnessUp, .illuminationUp: return 1
    case .soundDown, .brightnessDown, .illuminationDown: return -1
    case .mute: return 0
    }
  }
}

/// One decoded media-key event: which key, pressed or released, auto-repeat, and fine-step modifiers.
struct MediaKeyEvent: Equatable {
  let key: MediaKey
  let isDown: Bool
  let isRepeat: Bool
  /// Shift + Option, which macOS uses for quarter-size steps.
  let isFine: Bool

  static let auxiliaryControlSubtype: Int16 = 8
  /// `NX_SYSDEFINED`.
  static let systemDefinedType: UInt32 = 14

  /// Decodes the packed `data1` of an auxiliary-control event.
  /// Layout: bits 16-31 key code, bits 8-15 state (0xA down, 0xB up), bit 0 repeat.
  static func decode(subtype: Int16, data1: Int, modifiers: NSEvent.ModifierFlags) -> MediaKeyEvent? {
    guard subtype == auxiliaryControlSubtype else { return nil }
    let code = (data1 & 0xFFFF_0000) >> 16
    let flags = data1 & 0x0000_FFFF
    let state = (flags & 0xFF00) >> 8
    guard let key = MediaKey(rawValue: code), state == 0xA || state == 0xB else { return nil }
    let fine = modifiers.contains(.shift) && modifiers.contains(.option)
    return MediaKeyEvent(key: key, isDown: state == 0xA, isRepeat: flags & 0x1 == 1, isFine: fine)
  }

  static func decode(_ event: NSEvent) -> MediaKeyEvent? {
    guard event.type == .systemDefined else { return nil }
    return decode(subtype: event.subtype.rawValue, data1: event.data1, modifiers: event.modifierFlags)
  }
}
