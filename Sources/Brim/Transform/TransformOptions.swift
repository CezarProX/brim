import Foundation
import ImageIO
import UniformTypeIdentifiers

enum TransformQuality: String, Codable, CaseIterable, Identifiable {
  case small = "Smaller", balanced = "Balanced", high = "Best"
  var id: String { rawValue }
  /// Scale used when PDF pages are re-rendered.
  var pdfScale: CGFloat {
    switch self {
    case .small: 0.6
    case .balanced: 1.0
    case .high: 1.5
    }
  }
  var pdfJPEGQuality: Double {
    switch self {
    case .small: 0.5
    case .balanced: 0.7
    case .high: 0.85
    }
  }
}

/// Image output the user can pick. `automatic` keeps what suits the source.
enum TransformImageFormat: String, Codable, CaseIterable, Identifiable {
  case automatic = "Automatic", jpeg = "JPEG", heic = "HEIC", png = "PNG", webp = "WebP", tiff = "TIFF"
  var id: String { rawValue }

  var type: UTType? {
    switch self {
    case .automatic: nil
    case .jpeg: .jpeg
    case .heic: .heic
    case .png: .png
    case .webp: .webP
    case .tiff: .tiff
    }
  }

  /// Formats ImageIO can actually write on this Mac (WebP only on newer systems).
  static func writable(_ formats: [TransformImageFormat] = allCases) -> [TransformImageFormat] {
    let supported = Set(
      (CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? [])
    return formats.filter { format in
      guard let type = format.type else { return true }
      if format == .webp, OptionalTools.isAvailable(.cwebp) { return true }
      return supported.contains(type.identifier)
    }
  }

  var isLossy: Bool { self == .jpeg || self == .heic || self == .webp }
}

enum TransformVideoContainer: String, Codable, CaseIterable, Identifiable {
  case mp4 = "MP4", mov = "MOV", webm = "WebM", mkv = "MKV"
  var id: String { rawValue }
  var fileExtension: String { rawValue.lowercased() }
  /// WebM and MKV aren't AVFoundation containers; they need FFmpeg.
  var requiresFFmpeg: Bool { self == .webm || self == .mkv }

  /// The containers this Mac can write right now.
  static func available(ffmpeg: Bool = OptionalTools.isAvailable(.ffmpeg)) -> [TransformVideoContainer] {
    allCases.filter { ffmpeg || !$0.requiresFFmpeg }
  }
}

enum TransformResizeMode: String, Codable, CaseIterable, Identifiable {
  case maxDimension = "Longest side", percent = "Percent"
  var id: String { rawValue }
}

/// Every knob an operation reads. One value type so presets can save and replay it.
struct TransformOptions: Codable, Equatable {
  var imageQuality: Double = 0.72
  var imageFormat: TransformImageFormat = .automatic
  var videoQuality: TransformQuality = .balanced
  var pdfQuality: TransformQuality = .balanced
  /// Compress until the result is at most this many bytes (nil = use quality as given).
  var targetBytes: Int64?
  var resizeMode: TransformResizeMode = .maxDimension
  var maxDimension: Int = 1600
  /// Compress also caps the longest side at `maxDimension`.
  var limitLongestSide = false
  var percent: Int = 50
  /// Strip EXIF, GPS and other metadata while processing an image.
  var stripMetadata = false
  var convertFormat: TransformImageFormat = .jpeg
  var videoContainer: TransformVideoContainer = .mp4
  var gifFPS: Double = 12
  var gifWidth: Int = 480
  /// Seconds each picture stays when a GIF is made from several images.
  var gifImageDuration: Double = 0.8
  var trimStart: Double = 0
  /// Seconds; nil trims nothing off the end.
  var trimEnd: Double?
  var targetFPS: Double = 24
  /// Clockwise degrees: 90, 180 or 270.
  var rotation: Int = 90
  var renamePattern = "{name}-{n}"

  var clampedRotation: Int { ((rotation % 360) + 360) % 360 }
}

/// Where results go.
enum TransformDestination: String, Codable, CaseIterable, Identifiable {
  case nextToOriginal = "Next to the original", downloads = "Downloads"
  var id: String { rawValue }
}

struct TransformOutputPolicy: Equatable {
  var destination: TransformDestination = .nextToOriginal
  var moveOriginalsToTrash = false
  var revealInFinder = false
}

/// A saved recipe: one operation plus its options.
struct TransformPreset: Codable, Identifiable, Equatable {
  var id: String
  var name: String
  var symbol: String
  var operation: TransformOperation
  var options: TransformOptions
  var isBuiltIn = false

  static func webReady(webP: Bool = TransformImageFormat.writable([.webp]).contains(.webp)) -> TransformPreset {
    var options = TransformOptions()
    options.imageFormat = webP ? .webp : .jpeg
    options.imageQuality = 0.8
    options.maxDimension = 1600
    options.limitLongestSide = true
    options.stripMetadata = true
    return TransformPreset(
      id: "builtin.web", name: "Web ready", symbol: "globe", operation: .compress, options: options,
      isBuiltIn: true)
  }

  static let under10MB: TransformPreset = {
    var options = TransformOptions()
    options.targetBytes = 10 * 1_000_000
    options.imageFormat = .jpeg
    return TransformPreset(
      id: "builtin.under10", name: "Under 10 MB", symbol: "scalemass", operation: .compress,
      options: options, isBuiltIn: true)
  }()

  static let lightPDF: TransformPreset = {
    var options = TransformOptions()
    options.pdfQuality = .small
    return TransformPreset(
      id: "builtin.lightpdf", name: "Light PDF", symbol: "doc.text", operation: .compress,
      options: options, isBuiltIn: true)
  }()

  static let chatGIF: TransformPreset = {
    var options = TransformOptions()
    options.gifFPS = 12
    options.gifWidth = 480
    return TransformPreset(
      id: "builtin.chatgif", name: "Chat GIF", symbol: "bubble.left.fill", operation: .makeGIF,
      options: options, isBuiltIn: true)
  }()

  static var builtIn: [TransformPreset] { [webReady(), under10MB, lightPDF, chatGIF] }

  /// Presets whose operation applies to all of these files.
  static func applicable(_ presets: [TransformPreset], to urls: [URL]) -> [TransformPreset] {
    let available = Set(TransformOperation.available(for: urls))
    let kinds = Set(urls.map(TransformFileKind.init(url:)))
    return presets.filter { preset in
      guard available.contains(preset.operation) else { return false }
      // Light PDF only makes sense for PDFs; Web ready and Under 10 MB for images.
      switch preset.id {
      case "builtin.lightpdf": return kinds == [.pdf]
      case "builtin.web", "builtin.under10": return kinds == [.image]
      default: return true
      }
    }
  }
}
