// TextCaptureModel.swift
// Brim
//
// Runs a capture end to end: pick pixels -> Vision (text + codes) -> history -> completion action.

import AppKit
import PDFKit
import SwiftUI

struct TextCaptureResult: Equatable {
  var text: String
  var codes: [DetectedCode]
  var source: TextCaptureEntry.Source
  var pages: Int?
  var isEmpty: Bool { text.isEmpty && codes.isEmpty }
  var payloads: [CodePayload] { codes.map { CodePayload.classify($0.payload, symbology: $0.symbology) } }
}

@MainActor
final class TextCaptureModel: ObservableObject {
  static let shared = TextCaptureModel()
  @Published private(set) var result: TextCaptureResult?
  @Published private(set) var isWorking = false
  @Published private(set) var progress: String?
  @Published private(set) var notice: String?
  /// True when macOS has not let Brim see the screen; the view offers the Settings pane.
  @Published private(set) var needsScreenAccess = false

  /// Set by the shell: open the island on the Text Capture view so the result is visible.
  var onShowResult: (() -> Void)?

  private let settings: AppSettings
  private let history: TextCaptureHistory

  init(settings: AppSettings = .shared, history: TextCaptureHistory? = nil) {
    self.settings = settings
    self.history = history ?? .shared
  }

  func captureArea() async {
    guard !isWorking else { return }
    guard CGPreflightScreenCaptureAccess() else {
      // Without it the selection tool returns only the wallpaper, which reads as "no text found".
      needsScreenAccess = true
      notice = nil
      _ = CGRequestScreenCaptureAccess()
      return
    }
    needsScreenAccess = false
    isWorking = true
    defer { isWorking = false; progress = nil }
    // Close the island first so it is not in the picture and the crosshair gets the screen.
    NotchShelfController.shared.dismissShelf()
    try? await Task.sleep(for: .milliseconds(250))
    guard let image = await TextCaptureSources.selectArea() else { return }
    await process([image], source: .area)
  }

  func chooseFile() async {
    guard !isWorking, let url = TextCaptureSources.chooseFile() else { return }
    await read(file: url)
  }

  func read(file url: URL) async {
    guard !isWorking else { return }
    isWorking = true
    defer { isWorking = false; progress = nil }
    if url.pathExtension.lowercased() == "pdf" {
      guard let document = PDFDocument(url: url), !document.isLocked else {
        notice = "That PDF can’t be opened (it may be locked)."
        return
      }
      progress = "Rendering \(min(document.pageCount, TextCaptureSources.maxPDFPages)) pages…"
      let images = await Task.detached(priority: .userInitiated) { TextCaptureSources.renderPages(of: document) }.value
      await process(images, source: .pdf)
    } else if let image = TextCaptureSources.loadImage(at: url) {
      await process([image], source: .image)
    } else {
      notice = "That file isn’t an image Brim can read."
    }
  }

  /// Runs recognition over `images` (pages are joined in order) and applies the completion action.
  func process(_ images: [CGImage], source: TextCaptureEntry.Source) async {
    let language = settings.textCaptureLanguage
    let correction = settings.textCaptureLanguageCorrection
    notice = nil
    var texts: [String] = []
    var codes: [DetectedCode] = []
    for (index, image) in images.enumerated() {
      if images.count > 1 { progress = "Reading page \(index + 1) of \(images.count)…" }
      let found = await Task.detached(priority: .userInitiated) {
        (TextRecognition.recognizeText(in: image, language: language, correction: correction),
         TextRecognition.detectCodes(in: image))
      }.value
      if !found.0.isEmpty { texts.append(found.0) }
      codes += found.1.filter { !codes.contains($0) }
    }
    let result = TextCaptureResult(
      text: texts.joined(separator: "\n\n"), codes: codes, source: source, pages: source == .pdf ? images.count : nil)
    finish(result)
  }

  private func finish(_ result: TextCaptureResult) {
    guard !result.isEmpty else {
      notice = "No text or codes found"
      IslandFlashCenter.shared.show("No text found", symbol: "text.viewfinder", tint: .white)
      return
    }
    self.result = result
    record(result)
    let completion = settings.textCaptureCompletion
    var copied = false
    if settings.textCaptureAutoCopyCodes, let first = result.payloads.first {
      copy(first.copyValue)
      copied = true
    } else if completion.copies {
      copy(result.text.isEmpty ? (result.payloads.first?.copyValue ?? "") : result.text)
      copied = true
    }
    if copied {
      IslandFlashCenter.shared.show(result.text.isEmpty ? "Code copied" : "Text copied", symbol: "text.viewfinder", tint: .teal)
    }
    if completion.shows { onShowResult?() }
  }

  private func record(_ result: TextCaptureResult) {
    guard settings.textCaptureKeepHistory else { return }
    if !result.text.isEmpty {
      history.add(TextCaptureEntry(kind: .text, source: result.source, text: result.text, pages: result.pages))
    }
    for code in result.codes {
      history.add(TextCaptureEntry(kind: .code, source: result.source, text: code.payload, symbology: code.symbology))
    }
  }

  func copy(_ text: String) {
    guard !text.isEmpty else { return }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
  }

  func open(_ url: URL) {
    guard let scheme = url.scheme?.lowercased(), ["http", "https", "mailto", "tel", "sms"].contains(scheme) else { return }
    NSWorkspace.shared.open(url)
  }

  func show(_ entry: TextCaptureEntry) {
    result = TextCaptureResult(
      text: entry.kind == .text ? entry.text : "",
      codes: entry.kind == .code ? [DetectedCode(payload: entry.text, symbology: entry.symbology ?? "QR code")] : [],
      source: entry.source, pages: entry.pages)
  }
}

@MainActor
final class TextCaptureController {
  static let shared = TextCaptureController()
  private let settings = AppSettings.shared
  private init() {}

  func start() {
    stop()
    guard settings.textCaptureEnabled else { return }
    DropletHotkeyCenter.shared.register(.textCapture, shortcut: settings.textCaptureShortcut) {
      Task { await TextCaptureModel.shared.captureArea() }
    }
  }

  func stop() { DropletHotkeyCenter.shared.unregister(.textCapture) }
  func settingsChanged() { settings.textCaptureEnabled ? start() : stop() }
}
