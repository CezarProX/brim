// TextCaptureSources.swift
// Brim
//
// Where images come from: a dragged screen area (the system selection tool, as the Ring's
// Grab Text does), an image file, or the pages of a PDF.

import AppKit
import PDFKit

enum TextCaptureSources {
  /// Lets the user drag out a region. Returns nil if they cancel.
  static func selectArea() async -> CGImage? {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("brim-textcapture-\(UUID().uuidString).png")
    defer { try? FileManager.default.removeItem(at: file) }
    let captured: Bool = await withCheckedContinuation { continuation in
      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
      process.arguments = ["-i", "-x", file.path]
      process.terminationHandler = { _ in continuation.resume(returning: FileManager.default.fileExists(atPath: file.path)) }
      do { try process.run() } catch { continuation.resume(returning: false) }
    }
    guard captured else { return nil }
    return loadImage(at: file)
  }

  static func loadImage(at url: URL) -> CGImage? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
  }

  static let maxPDFPages = 40

  /// Renders PDF pages at about 2x for recognition. At most `maxPDFPages` pages.
  static func renderPages(of document: PDFDocument, scale: CGFloat = 2) -> [CGImage] {
    (0..<min(document.pageCount, maxPDFPages)).compactMap { index in
      guard let page = document.page(at: index) else { return nil }
      let bounds = page.bounds(for: .mediaBox)
      let width = Int(bounds.width * scale), height = Int(bounds.height * scale)
      guard width > 0, height > 0, width * height < 120_000_000,
        let context = CGContext(
          data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
      else { return nil }
      context.setFillColor(CGColor(gray: 1, alpha: 1))
      context.fill(CGRect(x: 0, y: 0, width: width, height: height))
      context.scaleBy(x: scale, y: scale)
      page.draw(with: .mediaBox, to: context)
      return context.makeImage()
    }
  }

  @MainActor
  static func chooseFile() -> URL? {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.image, .pdf]
    panel.allowsMultipleSelection = false
    panel.message = "Choose an image or PDF to read text from"
    return panel.runModal() == .OK ? panel.url : nil
  }
}
