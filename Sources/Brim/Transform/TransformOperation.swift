import Foundation
import UniformTypeIdentifiers

/// What kind of media a file is, as far as Transform cares.
enum TransformFileKind: String, CaseIterable {
  case image, video, audio, pdf, archive, other

  init(type: UTType?) {
    guard let type else { self = .other; return }
    if type.conforms(to: .pdf) { self = .pdf }
    else if type.conforms(to: .image) { self = .image }
    else if type.conforms(to: .movie) || type.conforms(to: .video) { self = .video }
    else if type.conforms(to: .audio) { self = .audio }
    else if type.conforms(to: .archive) { self = .archive }
    else { self = .other }
  }

  init(url: URL) {
    // 7z, RAR and friends have no system type on a Mac without the app, so go by extension.
    if ArchiveFormat.isExtractable(url) { self = .archive; return }
    let type = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)
      ?? UTType(filenameExtension: url.pathExtension)
    self.init(type: type)
  }
}

enum TransformGroup: String, CaseIterable, Identifiable {
  case size = "Size", format = "Format", edit = "Edit", files = "Files"
  var id: String { rawValue }
}

/// Everything Transform can do to a file. Each runs on device with Apple frameworks.
enum TransformOperation: String, CaseIterable, Identifiable, Codable {
  case compress, resize
  case convert, makeGIF, extractAudio, combinePDF, splitPDF
  case rotate, trim, frameRate, removeAudio, removeMetadata, removeBackground
  case zip, extract, rename

  var id: String { rawValue }

  var title: String {
    switch self {
    case .compress: "Compress"
    case .resize: "Resize"
    case .convert: "Convert"
    case .makeGIF: "Make GIF"
    case .extractAudio: "Extract Audio"
    case .combinePDF: "Combine to PDF"
    case .splitPDF: "Split Pages"
    case .rotate: "Rotate"
    case .trim: "Trim"
    case .frameRate: "Frame Rate"
    case .removeAudio: "Remove Audio"
    case .removeMetadata: "Remove Metadata"
    case .removeBackground: "Remove Background"
    case .zip: "Zip"
    case .extract: "Extract"
    case .rename: "Rename"
    }
  }

  var symbol: String {
    switch self {
    case .compress: "arrow.down.right.and.arrow.up.left"
    case .resize: "arrow.up.left.and.arrow.down.right"
    case .convert: "arrow.triangle.2.circlepath"
    case .makeGIF: "photo.on.rectangle.angled"
    case .extractAudio: "waveform"
    case .combinePDF: "doc.on.doc"
    case .splitPDF: "rectangle.split.2x1"
    case .rotate: "rotate.right"
    case .trim: "scissors"
    case .frameRate: "speedometer"
    case .removeAudio: "speaker.slash"
    case .removeMetadata: "eye.slash"
    case .removeBackground: "person.crop.circle.badge.minus"
    case .zip: "doc.zipper"
    case .extract: "archivebox"
    case .rename: "textformat"
    }
  }

  var group: TransformGroup {
    switch self {
    case .compress, .resize: .size
    case .convert, .makeGIF, .extractAudio, .combinePDF, .splitPDF: .format
    case .rotate, .trim, .frameRate, .removeAudio, .removeMetadata, .removeBackground: .edit
    case .zip, .extract, .rename: .files
    }
  }

  /// The file kinds this operation can take as input.
  var supportedKinds: Set<TransformFileKind> {
    switch self {
    case .compress: [.image, .video, .pdf]
    case .resize: [.image]
    case .convert: [.image, .video, .audio]
    case .makeGIF: [.video, .image]
    case .extractAudio: [.video]
    case .combinePDF: [.image, .pdf]
    case .splitPDF: [.pdf]
    case .rotate: [.image, .video, .pdf]
    case .trim: [.video, .audio]
    case .frameRate, .removeAudio: [.video]
    case .removeMetadata: [.image, .pdf]
    case .removeBackground: [.image]
    case .zip, .rename: Set(TransformFileKind.allCases)
    case .extract: [.archive]
    }
  }

  /// True when all the files feed one result (a combined PDF, one GIF, one archive).
  func isGroupOperation(fileCount: Int) -> Bool {
    switch self {
    case .combinePDF, .zip: fileCount > 1
    case .makeGIF: fileCount > 1
    case .rename: true
    default: false
    }
  }

  func isAvailable(for type: UTType?) -> Bool { supportedKinds.contains(TransformFileKind(type: type)) }
  func isAvailable(for kind: TransformFileKind) -> Bool { supportedKinds.contains(kind) }

  /// Operations that apply to every one of these files.
  static func available(for urls: [URL]) -> [TransformOperation] {
    let kinds = urls.map(TransformFileKind.init(url:))
    guard !kinds.isEmpty else { return [] }
    return allCases.filter { operation in kinds.allSatisfy(operation.isAvailable(for:)) }
  }

  /// The operation worth selecting first for a given set of files.
  static func suggested(for urls: [URL]) -> TransformOperation? {
    let operations = available(for: urls)
    for candidate in [TransformOperation.compress, .convert, .zip] where operations.contains(candidate) {
      return candidate
    }
    return operations.first
  }
}
