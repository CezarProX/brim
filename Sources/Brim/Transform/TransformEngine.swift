import Foundation

/// What happened to one unit of work (a file, or a group of files that feed one result).
struct TransformOutcome: Equatable, Sendable {
  var outputs: [URL]
  var bytesBefore: Int64
  var bytesAfter: Int64
  var note: String?

  var summary: String { TransformSizeSummary.text(before: bytesBefore, after: bytesAfter) }
}

enum TransformUnitState: Equatable, Sendable {
  case waiting
  case running(Double)
  case done(TransformOutcome)
  case skipped(String)
  case failed(String)
  case cancelled
}

/// Runs a Transform operation over files, sequentially, off the main actor.
/// Originals are never modified: every result is a new, non-colliding file.
enum TransformEngine {
  /// Splits files into units. Group operations take all the files at once.
  static func units(for urls: [URL], operation: TransformOperation) -> [[URL]] {
    operation.isGroupOperation(fileCount: urls.count) ? [urls] : urls.map { [$0] }
  }

  /// Runs every unit in order, reporting state changes; stops promptly on cancellation.
  static func run(
    units: [[URL]], operation: TransformOperation, options: TransformOptions,
    policy: TransformOutputPolicy, downloads: URL? = nil,
    onUpdate: @escaping @Sendable (Int, TransformUnitState) -> Void
  ) async {
    for (index, sources) in units.enumerated() {
      if Task.isCancelled {
        for rest in index..<units.count { onUpdate(rest, .cancelled) }
        return
      }
      onUpdate(index, .running(0))
      let context = TransformContext(policy: policy, downloads: downloads) { value in
        onUpdate(index, .running(min(1, max(0, value))))
      }
      do {
        let outcome = try await process(sources, operation: operation, options: options, context: context)
        onUpdate(index, outcome.outputs.isEmpty ? .skipped(outcome.note ?? "Nothing to do") : .done(outcome))
      } catch TransformError.cancelled {
        onUpdate(index, .cancelled)
      } catch is CancellationError {
        onUpdate(index, .cancelled)
      } catch {
        onUpdate(index, .failed(error.localizedDescription))
      }
    }
  }

  static func process(
    _ sources: [URL], operation: TransformOperation, options: TransformOptions, context: TransformContext
  ) async throws -> TransformOutcome {
    let before = sources.reduce(Int64(0)) { $0 + fileSize($1) }
    let outputs = try await perform(operation, sources: sources, options: options, context: context)
    let after = outputs.reduce(Int64(0)) { $0 + fileSize($1) }
    var note: String?
    if operation == .compress, outputs.count == 1, after >= before, before > 0 {
      // A "compressed" copy that is not smaller is noise; keep the original and say so.
      outputs.forEach { try? FileManager.default.removeItem(at: $0) }
      return TransformOutcome(outputs: [], bytesBefore: before, bytesAfter: before, note: "Already as small as it gets")
    }
    if context.policy.moveOriginalsToTrash, operation != .rename {
      note = trash(sources, keeping: outputs)
    }
    return TransformOutcome(outputs: outputs, bytesBefore: before, bytesAfter: after, note: note)
  }

  /// Dispatches one operation to its implementation.
  static func perform(
    _ operation: TransformOperation, sources: [URL], options: TransformOptions, context: TransformContext
  ) async throws -> [URL] {
    guard let first = sources.first else { return [] }
    let kind = TransformFileKind(url: first)
    try context.checkCancelled()
    switch operation {
    case .compress:
      switch kind {
      case .image: return [try ImageTransforms.compress(first, options: options, context: context)]
      case .video: return [try await AVTransforms.compressVideo(first, options: options, context: context)]
      case .pdf: return [try PDFTransforms.compress(first, quality: options.pdfQuality, context: context)]
      default: throw TransformError.unsupported("Compress")
      }
    case .resize: return [try ImageTransforms.resize(first, options: options, context: context)]
    case .convert:
      switch kind {
      case .image: return [try ImageTransforms.convert(first, options: options, context: context)]
      case .video: return [try await AVTransforms.convertVideo(first, options: options, context: context)]
      case .audio: return [try await AVTransforms.exportAudio(first, suffix: "", context: context)]
      default: throw TransformError.unsupported("Convert")
      }
    case .makeGIF:
      if kind == .video { return [try await AVTransforms.makeGIF(fromVideo: first, options: options, context: context)] }
      return [try AVTransforms.makeGIF(fromImages: sources, options: options, context: context)]
    case .extractAudio: return [try await AVTransforms.exportAudio(first, suffix: "audio", context: context)]
    case .removeAudio: return [try await AVTransforms.removeAudio(first, context: context)]
    case .trim:
      return [kind == .audio
        ? try await AVTransforms.trimAudio(first, options: options, context: context)
        : try await AVTransforms.trimVideo(first, options: options, context: context)]
    case .frameRate:
      return [try await AVTransforms.recompose(first, fps: options.targetFPS, rotation: 0, suffix: "\(Int(options.targetFPS))fps", context: context)]
    case .rotate:
      switch kind {
      case .image: return [try ImageTransforms.rotate(first, options: options, context: context)]
      case .pdf: return [try PDFTransforms.rotate(first, degrees: options.clampedRotation, context: context)]
      default: return [try await AVTransforms.recompose(first, fps: nil, rotation: options.clampedRotation, suffix: "rotated", context: context)]
      }
    case .removeMetadata:
      return [kind == .pdf
        ? try PDFTransforms.stripMetadata(first, context: context)
        : try ImageTransforms.stripMetadata(first, context: context)]
    case .removeBackground: return [try removeBackground(first, context: context)]
    case .combinePDF: return [try PDFTransforms.combine(sources, context: context)]
    case .splitPDF: return try PDFTransforms.split(first, context: context)
    case .zip: return [try ArchiveTransforms.zip(sources, context: context)]
    case .extract: return [try ArchiveTransforms.extract(first, context: context)]
    case .rename: return try rename(sources, pattern: options.renamePattern)
    }
  }

  private static func removeBackground(_ source: URL, context: TransformContext) throws -> URL {
    let image = try FileTrayStore.cutoutImage(source)
    let data = try ImageTransforms.encode(image, as: .png, quality: 1)
    let output = context.output(for: source, suffix: "cutout", fileExtension: "png")
    try ImageTransforms.write(data, to: output)
    return output
  }

  /// Renames in place with the pattern. Never replaces a file that already has the target name.
  static func rename(_ sources: [URL], pattern: String, date: Date = .now) throws -> [URL] {
    var results: [URL] = []
    for (offset, source) in sources.enumerated() {
      let stem = TransformNaming.renamed(
        pattern: pattern, originalName: source.deletingPathExtension().lastPathComponent,
        index: offset + 1, date: date)
      let folder = source.deletingLastPathComponent()
      let ext = source.pathExtension
      let direct = ext.isEmpty ? folder.appendingPathComponent(stem) : folder.appendingPathComponent(stem).appendingPathExtension(ext)
      if direct.path == source.path { results.append(source); continue }
      let target = TransformNaming.uniqueURL(in: folder, name: stem, fileExtension: ext)
      do { try FileManager.default.moveItem(at: source, to: target) } catch {
        throw TransformError.failed("Couldn’t rename \(source.lastPathComponent).")
      }
      results.append(target)
    }
    return results
  }

  /// Moves originals to the Trash, but never anything a result is (or lives inside).
  private static func trash(_ sources: [URL], keeping outputs: [URL]) -> String? {
    let keep = Set(outputs.map(\.standardizedFileURL.path))
    var failures = 0
    for source in sources where !keep.contains(source.standardizedFileURL.path) {
      do { try FileManager.default.trashItem(at: source, resultingItemURL: nil) } catch { failures += 1 }
    }
    return failures == 0 ? nil : "Couldn’t move \(failures) original\(failures == 1 ? "" : "s") to the Trash"
  }

  static func fileSize(_ url: URL) -> Int64 {
    let keys: Set<URLResourceKey> = [.fileSizeKey, .isDirectoryKey]
    guard let values = try? url.resourceValues(forKeys: keys) else { return 0 }
    if values.isDirectory == true {
      let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey])
      var total: Int64 = 0
      while let item = walker?.nextObject() as? URL {
        total += Int64((try? item.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
      }
      return total
    }
    return Int64(values.fileSize ?? 0)
  }
}
