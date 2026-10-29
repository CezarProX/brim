import AVFoundation
import AppKit
import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

@testable import Brim

/// Small generated media for integration tests. Everything lives in a temp folder.
struct TransformFixtures {
  let folder: URL

  init() throws {
    folder = FileManager.default.temporaryDirectory.appendingPathComponent("QS-TF-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  }

  func cleanup() { try? FileManager.default.removeItem(at: folder) }

  /// Deterministic noise so lossy compression has something to bite on.
  static func noiseImage(width: Int, height: Int, seed: UInt64 = 7) -> CGImage {
    var state = seed
    var pixels = [UInt8](repeating: 255, count: width * height * 4)
    for index in stride(from: 0, to: pixels.count, by: 4) {
      state = state &* 6364136223846793005 &+ 1442695040888963407
      let value = UInt8(truncatingIfNeeded: state >> 33)
      pixels[index] = value
      pixels[index + 1] = UInt8(truncatingIfNeeded: Int(value) / 2 + (index / 4 % width) * 255 / width / 2)
      pixels[index + 2] = UInt8(truncatingIfNeeded: (index / 4 / width) * 255 / height)
    }
    let provider = CGDataProvider(data: Data(pixels) as CFData)!
    return CGImage(
      width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
      provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
  }

  /// A JPEG/PNG with EXIF and GPS metadata.
  @discardableResult
  func image(_ name: String, width: Int = 400, height: Int = 300, type: UTType = .jpeg, withMetadata: Bool = true) throws -> URL {
    let url = folder.appendingPathComponent(name)
    let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)!
    var properties: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 1.0]
    if withMetadata {
      properties[kCGImagePropertyExifDictionary] = [kCGImagePropertyExifUserComment: "secret comment"]
      properties[kCGImagePropertyGPSDictionary] = [
        kCGImagePropertyGPSLatitude: 44.4, kCGImagePropertyGPSLatitudeRef: "N",
        kCGImagePropertyGPSLongitude: 26.1, kCGImagePropertyGPSLongitudeRef: "E",
      ]
      properties[kCGImagePropertyTIFFDictionary] = [kCGImagePropertyTIFFMake: "TestCam"]
    }
    CGImageDestinationAddImage(destination, Self.noiseImage(width: width, height: height), properties as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { throw TransformError.failed("fixture") }
    return url
  }

  func pdf(_ name: String, pages: Int, title: String? = nil) throws -> URL {
    let document = PDFDocument()
    for index in 0..<pages {
      let image = NSImage(cgImage: Self.noiseImage(width: 120, height: 160, seed: UInt64(index + 1)), size: NSSize(width: 120, height: 160))
      document.insert(PDFPage(image: image)!, at: index)
    }
    if let title { document.documentAttributes = [PDFDocumentAttribute.titleAttribute: title, PDFDocumentAttribute.authorAttribute: "Someone"] }
    let url = folder.appendingPathComponent(name)
    guard document.write(to: url) else { throw TransformError.failed("fixture pdf") }
    return url
  }

  /// A 2 second, 10 fps, 64x48 video of changing noise.
  func video(_ name: String, seconds: Int = 2, fps: Int = 10) async throws -> URL {
    let url = folder.appendingPathComponent(name)
    let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
      AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 48,
    ])
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
      kCVPixelBufferWidthKey as String: 64, kCVPixelBufferHeightKey as String: 48,
    ])
    writer.add(input)
    writer.startWriting()
    writer.startSession(atSourceTime: .zero)
    for frame in 0..<(seconds * fps) {
      while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
      var buffer: CVPixelBuffer?
      CVPixelBufferCreate(nil, 64, 48, kCVPixelFormatType_32BGRA, nil, &buffer)
      guard let buffer else { continue }
      CVPixelBufferLockBaseAddress(buffer, [])
      if let base = CVPixelBufferGetBaseAddress(buffer) {
        memset(base, Int32((frame * 17) % 255), CVPixelBufferGetDataSize(buffer))
      }
      CVPixelBufferUnlockBaseAddress(buffer, [])
      adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(fps)))
    }
    input.markAsFinished()
    await writer.finishWriting()
    guard writer.status == .completed else { throw TransformError.failed("fixture video: \(String(describing: writer.error))") }
    return url
  }

  static func properties(_ url: URL) -> [CFString: Any] {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return [:] }
    return (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]) ?? [:]
  }

  static func size(_ url: URL) -> Int64 { TransformEngine.fileSize(url) }
}
