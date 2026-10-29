// ReplyQRImage.swift
// Brim
//
// Turns the site's QR code into a crisp image for the island. The drawn canvas is decoded with
// Core Image and re-encoded at an exact module grid, so it stays sharp at any size; if decoding
// fails the original drawing is used as is.

import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

enum ReplyQRImage {
  static func image(for code: LinkCode) -> NSImage? {
    switch code {
    case .payload(let text): return encode(text)
    case .image(let data):
      if let text = decode(data), let crisp = encode(text) { return crisp }
      return NSImage(data: data)
    }
  }

  /// The text inside a QR code image, if Core Image finds one.
  static func decode(_ data: Data) -> String? {
    guard let image = CIImage(data: data),
      let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil,
                                options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
    else { return nil }
    let found = detector.features(in: image).compactMap { ($0 as? CIQRCodeFeature)?.messageString }
    return found.first { !$0.isEmpty }
  }

  /// About this many pixels across, so the tile stays sharp on Retina at any size.
  static let targetPixels: CGFloat = 512

  /// A QR code scaled by a whole number of pixels per module, so every edge stays hard.
  static func encode(_ text: String) -> NSImage? {
    guard !text.isEmpty else { return nil }
    let filter = CIFilter.qrCodeGenerator()
    filter.message = Data(text.utf8)
    filter.correctionLevel = "M"
    guard let output = filter.outputImage, output.extent.width > 0 else { return nil }
    let factor = max(1, (targetPixels / output.extent.width).rounded(.down))
    let scaled = output.samplingNearest().transformed(by: CGAffineTransform(scaleX: factor, y: factor))
    guard let cgImage = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
    return NSImage(cgImage: cgImage, size: scaled.extent.size)
  }

  /// Decodes a `data:image/...;base64,` URL from the page.
  static func data(fromDataURL url: String) -> Data? {
    guard url.hasPrefix("data:image/"), let comma = url.firstIndex(of: ",") else { return nil }
    return Data(base64Encoded: String(url[url.index(after: comma)...]))
  }
}
