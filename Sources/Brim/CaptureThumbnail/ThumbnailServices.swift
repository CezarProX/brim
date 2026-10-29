import AppKit

/// What a thumbnail's buttons do to the image. The live implementation reuses the app's copy,
/// save, editor and text recognition; tests inject a recording fake.
@MainActor
protocol ThumbnailServices: AnyObject {
  func copy(_ image: NSImage)
  /// Writes the image to the configured save folder; true when a file was written.
  func save(_ image: NSImage) -> Bool
  func edit(_ image: NSImage)
  func recognizeText(in image: NSImage) async -> String
  func copyText(_ text: String)
  /// A PNG of the image on disk, for dragging the capture into another app.
  func dragFile(for image: NSImage) -> URL?
}

@MainActor
final class LiveThumbnailServices: ThumbnailServices {
  static let shared = LiveThumbnailServices()

  func copy(_ image: NSImage) {
    CaptureActions.copyToClipboard(image)
  }

  func save(_ image: NSImage) -> Bool {
    ThumbnailSaver.save(image) != nil
  }

  /// Same contract as editing from the island: edits come back to Captures as a new entry.
  func edit(_ image: NSImage) {
    let editedID = UUID()
    ShelfEditorWindowController.open(image: image) { edited in
      ShelfEditorWindowController.keepEdited(edited, id: editedID)
    }
  }

  func recognizeText(in image: NSImage) async -> String {
    guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return "" }
    let language = AppSettings.shared.textCaptureLanguage
    let correction = AppSettings.shared.textCaptureLanguageCorrection
    return await Task.detached(priority: .userInitiated) {
      TextRecognition.recognizeText(in: cgImage, language: language, correction: correction)
    }.value
  }

  func copyText(_ text: String) {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(text, forType: .string)
  }

  func dragFile(for image: NSImage) -> URL? {
    ThumbnailSaver.dragFile(for: image)
  }
}
