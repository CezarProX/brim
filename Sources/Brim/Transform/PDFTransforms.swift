import AppKit
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

/// PDF operations on PDFKit. Synchronous; call off the main actor.
enum PDFTransforms {
  static func open(_ url: URL) throws -> PDFDocument {
    guard let document = PDFDocument(url: url) else { throw TransformError.unreadable(url.lastPathComponent) }
    if document.isLocked { throw TransformError.failed("\(url.lastPathComponent) is password protected.") }
    return document
  }

  /// Images and PDFs, in the order given, become one document.
  static func combine(_ sources: [URL], context: TransformContext) throws -> URL {
    guard let first = sources.first else { throw TransformError.failed("Nothing to combine.") }
    let combined = PDFDocument()
    for (index, source) in sources.enumerated() {
      try context.checkCancelled()
      context.progress(Double(index) / Double(sources.count))
      if TransformFileKind(url: source) == .pdf {
        let document = try open(source)
        for pageIndex in 0..<document.pageCount {
          if let page = document.page(at: pageIndex)?.copy() as? PDFPage {
            combined.insert(page, at: combined.pageCount)
          }
        }
      } else {
        let image = try ImageTransforms.decode(source)
        let nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        guard let page = PDFPage(image: nsImage) else { throw TransformError.unreadable(source.lastPathComponent) }
        combined.insert(page, at: combined.pageCount)
      }
    }
    let output = context.output(for: first, suffix: "combined", fileExtension: "pdf")
    guard combined.pageCount > 0, combined.write(to: output) else {
      throw TransformError.failed("Couldn’t write the combined PDF.")
    }
    return output
  }

  /// One PDF per page: "name-page-1.pdf".
  static func split(_ source: URL, context: TransformContext) throws -> [URL] {
    let document = try open(source)
    var outputs: [URL] = []
    for index in 0..<document.pageCount {
      try context.checkCancelled()
      context.progress(Double(index) / Double(max(1, document.pageCount)))
      guard let page = document.page(at: index)?.copy() as? PDFPage else { continue }
      let single = PDFDocument()
      single.insert(page, at: 0)
      let output = context.output(for: source, suffix: "page-\(index + 1)", fileExtension: "pdf")
      guard single.write(to: output) else { throw TransformError.failed("Couldn’t write page \(index + 1).") }
      outputs.append(output)
    }
    guard !outputs.isEmpty else { throw TransformError.failed("This PDF has no pages.") }
    return outputs
  }

  /// Re-renders each page as a JPEG at a lower resolution. Text stops being selectable,
  /// which is the price of the size drop; callers keep the original.
  static func compress(_ source: URL, quality: TransformQuality, context: TransformContext) throws -> URL {
    // Ghostscript, when installed, keeps text selectable; otherwise pages are re-rendered below.
    let target = context.output(for: source, suffix: "compressed", fileExtension: "pdf")
    if let result = ExternalCodecs.compressPDF(source, quality: quality, to: target) { return result }
    let document = try open(source)
    let output = PDFDocument()
    for index in 0..<document.pageCount {
      try context.checkCancelled()
      context.progress(Double(index) / Double(max(1, document.pageCount)))
      guard let page = document.page(at: index) else { continue }
      let bounds = page.bounds(for: .mediaBox)
      let scale = quality.pdfScale
      let pixelWidth = max(1, Int(bounds.width * scale))
      let pixelHeight = max(1, Int(bounds.height * scale))
      guard let image = render(page, width: pixelWidth, height: pixelHeight) else { continue }
      let nsImage = NSImage(cgImage: image, size: bounds.size)
      let options: [PDFPage.ImageInitializationOption: Any] = [
        .compressionQuality: quality.pdfJPEGQuality, .mediaBox: CGRect(origin: .zero, size: bounds.size),
      ]
      if let rebuilt = PDFPage(image: nsImage, options: options) { output.insert(rebuilt, at: output.pageCount) }
    }
    let url = context.output(for: source, suffix: "compressed", fileExtension: "pdf")
    guard output.pageCount > 0, output.write(to: url) else {
      throw TransformError.failed("Couldn’t compress \(source.lastPathComponent).")
    }
    return url
  }

  private static func render(_ page: PDFPage, width: Int, height: Int) -> CGImage? {
    guard let context = CGContext(
      data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    else { return nil }
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let bounds = page.bounds(for: .mediaBox)
    context.scaleBy(x: CGFloat(width) / bounds.width, y: CGFloat(height) / bounds.height)
    context.translateBy(x: -bounds.minX, y: -bounds.minY)
    page.draw(with: .mediaBox, to: context)
    return context.makeImage()
  }

  static func rotate(_ source: URL, degrees: Int, context: TransformContext) throws -> URL {
    let document = try open(source)
    for index in 0..<document.pageCount {
      if let page = document.page(at: index) { page.rotation = (page.rotation + degrees) % 360 }
    }
    let output = context.output(for: source, suffix: "rotated", fileExtension: "pdf")
    guard document.write(to: output) else { throw TransformError.failed("Couldn’t write the rotated PDF.") }
    return output
  }

  /// Clears title, author, subject, keywords and creator.
  static func stripMetadata(_ source: URL, context: TransformContext) throws -> URL {
    let document = try open(source)
    document.documentAttributes = [:]
    let output = context.output(for: source, suffix: "clean", fileExtension: "pdf")
    guard document.write(to: output) else { throw TransformError.failed("Couldn’t write the cleaned PDF.") }
    return output
  }
}
