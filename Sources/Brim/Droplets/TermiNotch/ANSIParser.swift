// ANSIParser.swift
// Brim
//
// A small VT100/xterm escape-sequence tokenizer: the subset common shells and CLI tools use.
// It turns a byte stream into events; `TerminalBuffer` applies them to a screen.

import Foundation

enum ANSIEvent: Equatable {
  case text(Character)
  /// C0 control: 7 bell, 8 backspace, 9 tab, 10 line feed, 13 carriage return.
  case control(UInt8)
  /// CSI sequence. `prefix` is "?" for private modes; `final` is the terminating byte.
  case csi(params: [Int], prefix: Character?, final: Character)
  /// ESC followed by a single character (7, 8, M, D, E, c ...).
  case escape(Character)
  /// OSC string (window title etc.), without the terminator.
  case osc(String)
}

struct ANSIParser {
  private enum State { case ground, escape, csi, osc, oscEscape, charset }
  private var state = State.ground
  private var params: [Int] = []
  private var current: Int?
  private var prefix: Character?
  private var oscBytes: [UInt8] = []
  private var utf8: [UInt8] = []
  private var utf8Needed = 0

  /// Feeds bytes and returns the events they complete. Incomplete sequences carry over to the next call.
  mutating func parse(_ data: Data) -> [ANSIEvent] {
    var events: [ANSIEvent] = []
    for byte in data { consume(byte, into: &events) }
    return events
  }

  private mutating func consume(_ byte: UInt8, into events: inout [ANSIEvent]) {
    switch state {
    case .ground: ground(byte, &events)
    case .escape: escape(byte, &events)
    case .csi: csi(byte, &events)
    case .osc:
      if byte == 0x07 { finishOSC(&events) } else if byte == 0x1B { state = .oscEscape } else if oscBytes.count < 512 {
        oscBytes.append(byte)
      }
    case .oscEscape:
      finishOSC(&events)  // ESC \ (string terminator)
    case .charset:
      state = .ground  // swallow the designator after ESC ( or ESC )
    }
  }

  private mutating func ground(_ byte: UInt8, _ events: inout [ANSIEvent]) {
    if utf8Needed > 0 {
      if byte & 0xC0 == 0x80 {
        utf8.append(byte)
        utf8Needed -= 1
        if utf8Needed == 0, let scalar = String(bytes: utf8, encoding: .utf8)?.first { events.append(.text(scalar)) }
        return
      }
      utf8Needed = 0
      utf8 = []
    }
    switch byte {
    case 0x1B: state = .escape
    case 0x07, 0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D: events.append(.control(byte == 0x0B || byte == 0x0C ? 0x0A : byte))
    case 0x20...0x7E: events.append(.text(Character(UnicodeScalar(byte))))
    case 0xC2...0xDF: begin(byte, needed: 1)
    case 0xE0...0xEF: begin(byte, needed: 2)
    case 0xF0...0xF4: begin(byte, needed: 3)
    default: break
    }
  }

  private mutating func begin(_ byte: UInt8, needed: Int) {
    utf8 = [byte]
    utf8Needed = needed
  }

  private mutating func escape(_ byte: UInt8, _ events: inout [ANSIEvent]) {
    switch byte {
    case UInt8(ascii: "["):
      state = .csi
      params = []; current = nil; prefix = nil
    case UInt8(ascii: "]"):
      state = .osc
      oscBytes = []
    case UInt8(ascii: "("), UInt8(ascii: ")"): state = .charset
    case 0x30...0x7E:
      events.append(.escape(Character(UnicodeScalar(byte))))
      state = .ground
    default: state = .ground
    }
  }

  private mutating func csi(_ byte: UInt8, _ events: inout [ANSIEvent]) {
    switch byte {
    case 0x30...0x39: current = min(99_999, (current ?? 0) * 10 + Int(byte - 0x30))
    case UInt8(ascii: ";"), UInt8(ascii: ":"):
      params.append(current ?? 0)
      current = nil
    case UInt8(ascii: "?"), UInt8(ascii: ">"), UInt8(ascii: "<"), UInt8(ascii: "="): prefix = Character(UnicodeScalar(byte))
    case 0x20...0x2F: break  // intermediate bytes are ignored
    case 0x40...0x7E:
      if let current { params.append(current) } else if !params.isEmpty { params.append(0) }
      events.append(.csi(params: params, prefix: prefix, final: Character(UnicodeScalar(byte))))
      state = .ground
    case 0x1B: state = .escape
    default: state = .ground
    }
  }

  private mutating func finishOSC(_ events: inout [ANSIEvent]) {
    events.append(.osc(String(decoding: oscBytes, as: UTF8.self)))
    oscBytes = []
    state = .ground
  }
}
