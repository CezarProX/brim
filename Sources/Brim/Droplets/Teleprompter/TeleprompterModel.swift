// TeleprompterModel.swift
// Brim
//
// Script, playback state and the frame timer. Hovering pauses; speed changes live.

import AppKit
import SwiftUI

@MainActor
final class TeleprompterModel: ObservableObject {
  static let shared = TeleprompterModel()
  @Published var script: String { didSet { settings.teleprompterScript = script; offset = 0 } }
  @Published private(set) var isPlaying = false
  @Published private(set) var offset: Double = 0
  @Published private(set) var speed: Int
  @Published var isHovering = false
  @Published var mirrored: Bool
  @Published var contentHeight: Double = 0
  @Published var fontSize: Int
  @Published private(set) var loadError: String?

  private let settings: AppSettings
  private var timer: Timer?
  private var lastTick = Date()

  init(settings: AppSettings = .shared) {
    self.settings = settings
    script = settings.teleprompterScript
    speed = settings.teleprompterSpeed
    mirrored = settings.teleprompterMirrored
    fontSize = settings.teleprompterFontSize
  }

  /// True while the scroll is actually moving.
  var isMoving: Bool { isPlaying && !(isHovering && settings.teleprompterHoverPause) }
  var progress: Double { TeleprompterMath.progress(offset: offset, contentHeight: contentHeight) }
  var remaining: String {
    TeleprompterMath.clock(TeleprompterMath.secondsRemaining(offset: offset, level: speed, contentHeight: contentHeight))
  }

  func togglePlay() { isPlaying ? pause() : play() }

  func play() {
    guard !TeleprompterMath.paragraphs(script).isEmpty else { return }
    if contentHeight > 0, offset >= contentHeight { offset = 0 }
    isPlaying = true
    lastTick = Date()
    guard timer == nil else { return }
    let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.tick() }
    }
    RunLoop.main.add(timer, forMode: .common)
    self.timer = timer
  }

  func pause() {
    isPlaying = false
    timer?.invalidate()
    timer = nil
  }

  func restart() { offset = 0 }

  func nudge(by points: Double) {
    offset = min(max(0, offset + points), max(contentHeight, 0))
  }

  func setSpeed(_ level: Int) {
    speed = TeleprompterMath.clampLevel(level)
    settings.teleprompterSpeed = speed
  }

  func faster() { setSpeed(speed + 1) }
  func slower() { setSpeed(speed - 1) }

  func setMirrored(_ value: Bool) {
    mirrored = value
    settings.teleprompterMirrored = value
  }

  func setFontSize(_ size: Int) {
    fontSize = min(48, max(16, size))
    settings.teleprompterFontSize = fontSize
  }

  /// Loads a plain-text or Markdown script. Large files are refused rather than truncated silently.
  func load(from url: URL) {
    loadError = nil
    do {
      let data = try Data(contentsOf: url, options: .mappedIfSafe)
      guard data.count <= TeleprompterMath.maxScriptLength * 4 else {
        loadError = "That file is too large for a script."
        return
      }
      guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
        loadError = "That file isn’t text."
        return
      }
      script = String(text.prefix(TeleprompterMath.maxScriptLength))
    } catch {
      loadError = "Couldn’t open the file: \(error.localizedDescription)"
    }
  }

  /// A short script to try the prompter with. Pass it through `L10n.tr` before use.
  static let sampleScript = "Hello, and welcome. This is a sample script for the teleprompter.\n\nThe words scroll up at a steady pace, so you can look at the camera instead of your notes. Use the arrow keys to change the speed, and press Space to pause.\n\nWhen you are ready, paste your own script and press Show prompter."

  func chooseFile() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.plainText, .text, .utf8PlainText, .rtf]
    panel.allowsMultipleSelection = false
    panel.message = "Choose a script"
    if panel.runModal() == .OK, let url = panel.url { load(from: url) }
  }

  func pasteFromClipboard() {
    if let text = NSPasteboard.general.string(forType: .string), !text.isEmpty {
      script = String(text.prefix(TeleprompterMath.maxScriptLength))
    }
  }

  private func tick() {
    let now = Date()
    defer { lastTick = now }
    guard isMoving else { return }
    let step = TeleprompterMath.advance(
      offset: offset, dt: now.timeIntervalSince(lastTick), level: speed, contentHeight: contentHeight)
    offset = step.offset
    if step.finished { pause() }
  }
}
