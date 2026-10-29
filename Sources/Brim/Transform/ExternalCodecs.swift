import CoreGraphics
import ImageIO
import Foundation
import UniformTypeIdentifiers

/// Transform steps that hand work to an optional tool (see `OptionalTools`).
enum ExternalCodecs {
  // MARK: WebP (cwebp)

  /// True when ImageIO on this Mac can write WebP itself.
  static var nativeWebP: Bool {
    ((CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? []).contains(UTType.webP.identifier)
  }

  static func cwebpArguments(quality: Double, input: URL, output: URL) -> [String] {
    let q = Int((min(1, max(0, quality)) * 100).rounded())
    return ["-quiet", "-q", String(q), "-metadata", "none", input.path, "-o", output.path]
  }

  static func encodeWebP(_ image: CGImage, quality: Double) throws -> Data {
    guard let tool = OptionalTools.url(for: .cwebp) else { throw TransformError.unsupported("WebP") }
    let folder = FileManager.default.temporaryDirectory
      .appendingPathComponent("Brim-WebP-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let input = folder.appendingPathComponent("in.png")
    let output = folder.appendingPathComponent("out.webp")
    try ImageTransforms.write(try ImageTransforms.encode(image, as: .png, quality: 1), to: input)
    try ExternalProcess.run(tool.path, cwebpArguments(quality: quality, input: input, output: output),
                            failure: "cwebp couldn’t encode the image.")
    return try Data(contentsOf: output)
  }

  // MARK: PDF (Ghostscript)

  static func ghostscriptSetting(_ quality: TransformQuality) -> String {
    switch quality {
    case .small: "/screen"
    case .balanced: "/ebook"
    case .high: "/printer"
    }
  }

  static func ghostscriptArguments(quality: TransformQuality, input: URL, output: URL) -> [String] {
    ["-sDEVICE=pdfwrite", "-dCompatibilityLevel=1.5", "-dPDFSETTINGS=\(ghostscriptSetting(quality))",
     "-dNOPAUSE", "-dQUIET", "-dBATCH", "-dSAFER", "-sOutputFile=\(output.path)", input.path]
  }

  /// Compresses with Ghostscript, keeping text selectable. Nil when Ghostscript isn't installed
  /// or fails, so the caller can fall back to PDFKit.
  static func compressPDF(_ source: URL, quality: TransformQuality, to output: URL) -> URL? {
    guard let tool = OptionalTools.url(for: .ghostscript) else { return nil }
    do {
      try ExternalProcess.run(tool.path, ghostscriptArguments(quality: quality, input: source, output: output))
      return FileManager.default.fileExists(atPath: output.path) ? output : nil
    } catch {
      try? FileManager.default.removeItem(at: output)
      return nil
    }
  }

  // MARK: Video (FFmpeg)

  static func ffmpegArguments(container: TransformVideoContainer, input: URL, output: URL) -> [String] {
    let codecs: [String]
    switch container {
    case .webm: codecs = ["-c:v", "libvpx-vp9", "-crf", "32", "-b:v", "0", "-c:a", "libopus"]
    default: codecs = ["-c:v", "libx264", "-crf", "23", "-preset", "medium", "-c:a", "aac"]
    }
    return ["-y", "-nostdin", "-loglevel", "error", "-i", input.path] + codecs + [output.path]
  }

  static func convertVideo(_ source: URL, container: TransformVideoContainer, to output: URL) throws {
    guard let tool = OptionalTools.url(for: .ffmpeg) else { throw TransformError.unsupported(container.rawValue) }
    do {
      try ExternalProcess.run(tool.path, ffmpegArguments(container: container, input: source, output: output),
                              failure: "FFmpeg couldn’t convert the video.")
    } catch {
      try? FileManager.default.removeItem(at: output)
      throw error
    }
  }
}
