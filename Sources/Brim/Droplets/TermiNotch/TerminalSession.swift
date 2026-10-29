// TerminalSession.swift
// Brim
//
// One tab: a PTY, its screen buffer, and the typed-command history for that tab.

import Foundation
import SwiftUI

@MainActor
final class TerminalSession: ObservableObject, Identifiable {
  let id = UUID()
  @Published private(set) var buffer: TerminalBuffer
  @Published private(set) var isAlive = false
  @Published private(set) var failure: String?
  /// True once the user has typed or pasted anything in this tab (hides the first-run hint).
  @Published private(set) var hasInput = false
  /// Lines the user typed and ran in this tab. In memory only; never stored while echo is off.
  @Published private(set) var history: [String] = []

  private let pty = PTYSession()
  private var parser = ANSIParser()
  private var line = ""
  private var pendingBytes = Data()
  private var flushScheduled = false
  private let startDirectory: String

  init(directory: String = NSHomeDirectory(), columns: Int = 80, rows: Int = 10) {
    startDirectory = directory
    buffer = TerminalBuffer(columns: columns, rows: rows)
  }

  var title: String {
    let name = buffer.title.isEmpty ? (startDirectory as NSString).lastPathComponent : buffer.title
    return name.isEmpty ? "shell" : name
  }
  var currentDirectory: String? { pty.currentDirectory }

  /// Starts the user's login shell. Safe to call repeatedly.
  func start() {
    guard !isAlive else { return }
    pty.onOutput = { [weak self] data in
      Task { @MainActor [weak self] in self?.receive(data) }
    }
    pty.onExit = { [weak self] _ in
      Task { @MainActor [weak self] in self?.isAlive = false }
    }
    do {
      try pty.start(cwd: startDirectory, columns: UInt16(buffer.columns), rows: UInt16(buffer.rows))
      isAlive = true
      failure = nil
    } catch {
      failure = error.localizedDescription
    }
  }

  func stop() {
    pty.terminate()
    isAlive = false
  }

  /// Sends exactly what the user typed (or pasted).
  func send(_ text: String) {
    guard isAlive else { return }
    hasInput = true
    track(text)
    pty.send(text)
  }

  /// Puts text on the command line WITHOUT running it (no newline is ever added).
  func insertWithoutRunning(_ text: String) {
    send(text.replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " "))
  }

  func resize(columns: Int, rows: Int) {
    guard columns >= 2, rows >= 1, columns != buffer.columns || rows != buffer.rows else { return }
    buffer.resize(columns: columns, rows: rows)
    pty.resize(columns: UInt16(columns), rows: UInt16(rows))
  }

  /// Fills the screen from canned output without a shell (previews and tests).
  func showPreview(_ output: String) {
    isAlive = true
    var updated = buffer
    updated.apply(parser.parse(Data(output.utf8)))
    buffer = updated
  }

  func clearScreen() { send("\u{0C}") }  // Ctrl-L, the shell redraws

  /// Clears what is on screen and the scrollback. At a prompt the shell redraws it; a running
  /// program is left alone (nothing is sent to it).
  func clearOutput() {
    var updated = buffer
    updated.clearScrollback()
    buffer = updated
    if isAlive, !buffer.inAlternateScreen { clearScreen() }
  }

  /// All the output in this tab (scrollback and screen) as plain text.
  var outputText: String { buffer.fullText }

  /// Pastes text so it can never run by itself: the shell holds it on the line until Return.
  func paste(_ text: String) {
    send(TerminalPaste.payload(text, bracketed: buffer.bracketedPaste))
  }

  private func receive(_ data: Data) {
    pendingBytes.append(data)
    guard !flushScheduled else { return }
    flushScheduled = true
    // Coalesce bursts (e.g. `cat bigfile`) into one buffer update per frame.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.016) { [weak self] in self?.flush() }
  }

  private func flush() {
    flushScheduled = false
    let bytes = pendingBytes
    pendingBytes = Data()
    var updated = buffer
    updated.apply(parser.parse(bytes))
    buffer = updated
  }

  private func track(_ text: String) {
    guard !buffer.inAlternateScreen, pty.isEchoing else { line = ""; return }
    for character in text {
      if character == "\r" || character == "\n" {
        let command = line.trimmingCharacters(in: .whitespaces)
        if !command.isEmpty, history.last != command { history = Array((history + [command]).suffix(100)) }
        line = ""
      } else if character == "\u{7F}" {
        line = String(line.dropLast())
      } else if character.unicodeScalars.allSatisfy({ $0.value >= 32 }) && line.count < 500 {
        line.append(character)
      } else {
        line = ""  // escapes (arrows, ctrl keys): the line is no longer what was typed
      }
    }
  }
}

/// Maps AppKit key events to the bytes a terminal expects.
enum TerminalKeyEncoder {
  static func bytes(characters: String, charactersIgnoringModifiers: String, keyCode: UInt16, control: Bool, option: Bool) -> String? {
    switch keyCode {
    case 126: return "\u{1B}[A"
    case 125: return "\u{1B}[B"
    case 124: return option ? "\u{1B}f" : "\u{1B}[C"
    case 123: return option ? "\u{1B}b" : "\u{1B}[D"
    case 115: return "\u{1B}[H"
    case 119: return "\u{1B}[F"
    case 117: return "\u{1B}[3~"
    case 116: return "\u{1B}[5~"
    case 121: return "\u{1B}[6~"
    case 51: return option ? "\u{1B}\u{7F}" : "\u{7F}"
    case 36, 76: return "\r"
    case 48: return "\t"  // Tab goes to the shell, which does the completing
    case 53: return "\u{1B}"
    default: break
    }
    if control, let scalar = charactersIgnoringModifiers.unicodeScalars.first {
      let value = scalar.value
      if value >= 0x61 && value <= 0x7A { return String(UnicodeScalar(value - 0x60)!) }
      if value == 0x5B { return "\u{1B}" }
      if value == 0x5C { return "\u{1C}" }
      if value == 0x5D { return "\u{1D}" }
    }
    guard !characters.isEmpty, characters.unicodeScalars.allSatisfy({ $0.value >= 32 && !(0xF700...0xF8FF).contains($0.value) }) else { return nil }
    return characters
  }
}


/// What a paste sends. Pasted text never contains a Return, so it is never run on arrival.
enum TerminalPaste {
  static func payload(_ text: String, bracketed: Bool) -> String {
    let unified = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    let trimmed = unified.trimmingCharacters(in: .newlines)
    guard trimmed.contains("\n") else { return trimmed }
    // A shell in bracketed-paste mode keeps the lines in its editor; otherwise one line, with `; `
    // between commands, so pressing Return once runs them as the user pasted them.
    if bracketed { return "\u{1B}[200~" + trimmed + "\u{1B}[201~" }
    return trimmed.split(separator: "\n", omittingEmptySubsequences: true).joined(separator: "; ")
  }
}
