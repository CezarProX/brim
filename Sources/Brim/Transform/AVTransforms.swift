@preconcurrency import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Video and audio operations built on AVFoundation export sessions.
enum AVTransforms {
  // MARK: Export plumbing

  private struct Job {
    var preset: String
    var fileType: AVFileType
    var timeRange: CMTimeRange?
    var videoComposition: AVVideoComposition?
  }

  private final class Box<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
  }

  /// Runs one export, forwarding progress and honoring task cancellation.
  private static func export(_ asset: AVAsset, job: Job, to output: URL, context: TransformContext) async throws {
    guard let session = AVAssetExportSession(asset: asset, presetName: job.preset)
    else { throw TransformError.unsupported("This preset") }
    session.outputURL = output
    session.outputFileType = job.fileType
    if let range = job.timeRange { session.timeRange = range }
    if let composition = job.videoComposition { session.videoComposition = composition }
    session.shouldOptimizeForNetworkUse = true
    let box = Box(session)
    let progressTask = Task {
      while !Task.isCancelled {
        context.progress(Double(box.value.progress))
        try? await Task.sleep(for: .milliseconds(120))
      }
    }
    await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        box.value.exportAsynchronously { continuation.resume() }
      }
    } onCancel: {
      box.value.cancelExport()
    }
    progressTask.cancel()
    switch session.status {
    case .completed: context.progress(1)
    case .cancelled:
      try? FileManager.default.removeItem(at: output)
      throw TransformError.cancelled
    default:
      try? FileManager.default.removeItem(at: output)
      throw TransformError.failed(session.error?.localizedDescription ?? "The export failed.")
    }
  }

  private static func videoContainer(of source: URL) -> (AVFileType, String) {
    ["mp4", "m4v"].contains(source.pathExtension.lowercased()) ? (.mp4, "mp4") : (.mov, "mov")
  }

  private static func timeRange(_ options: TransformOptions, duration: CMTime) -> CMTimeRange {
    let total = duration.seconds
    let start = min(max(0, options.trimStart), max(0, total - 0.1))
    let end = min(options.trimEnd ?? total, total)
    return CMTimeRange(
      start: CMTime(seconds: start, preferredTimescale: 600),
      end: CMTime(seconds: max(end, start + 0.1), preferredTimescale: 600))
  }

  // MARK: Operations

  static func compressVideo(_ source: URL, options: TransformOptions, context: TransformContext) async throws -> URL {
    let asset = AVURLAsset(url: source)
    let wanted: String
    switch options.videoQuality {
    case .small: wanted = AVAssetExportPreset960x540
    case .balanced: wanted = AVAssetExportPreset1280x720
    case .high: wanted = AVAssetExportPreset1920x1080
    }
    let supported = await AVAssetExportSession.compatibility(ofExportPreset: wanted, with: asset, outputFileType: .mp4)
    let preset = supported ? wanted : AVAssetExportPresetMediumQuality
    let output = context.output(for: source, suffix: "compressed", fileExtension: "mp4")
    try await export(asset, job: Job(preset: preset, fileType: .mp4), to: output, context: context)
    return output
  }

  static func convertVideo(_ source: URL, options: TransformOptions, context: TransformContext) async throws -> URL {
    let asset = AVURLAsset(url: source)
    let mp4 = options.videoContainer == .mp4
    let output = context.output(for: source, suffix: "", fileExtension: options.videoContainer.fileExtension)
    if options.videoContainer.requiresFFmpeg {
      try ExternalCodecs.convertVideo(source, container: options.videoContainer, to: output)
      return output
    }
    try await export(
      asset, job: Job(preset: AVAssetExportPresetHighestQuality, fileType: mp4 ? .mp4 : .mov),
      to: output, context: context)
    return output
  }

  /// Audio-only export to AAC in an .m4a container. Used to convert audio and to pull it from video.
  static func exportAudio(_ source: URL, suffix: String, range options: TransformOptions? = nil, context: TransformContext) async throws -> URL {
    let asset = AVURLAsset(url: source)
    var job = Job(preset: AVAssetExportPresetAppleM4A, fileType: .m4a)
    if let options { job.timeRange = timeRange(options, duration: try await asset.load(.duration)) }
    let output = context.output(for: source, suffix: suffix, fileExtension: "m4a")
    try await export(asset, job: job, to: output, context: context)
    return output
  }

  static func removeAudio(_ source: URL, context: TransformContext) async throws -> URL {
    let asset = AVURLAsset(url: source)
    let composition = AVMutableComposition()
    let duration = try await asset.load(.duration)
    for track in try await asset.loadTracks(withMediaType: .video) {
      guard let target = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
      else { continue }
      try target.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: track, at: .zero)
      target.preferredTransform = try await track.load(.preferredTransform)
    }
    guard !composition.tracks.isEmpty else { throw TransformError.failed("This file has no video.") }
    let (type, ext) = videoContainer(of: source)
    let output = context.output(for: source, suffix: "silent", fileExtension: ext)
    try await export(composition, job: Job(preset: AVAssetExportPresetPassthrough, fileType: type), to: output, context: context)
    return output
  }

  static func trimVideo(_ source: URL, options: TransformOptions, context: TransformContext) async throws -> URL {
    let asset = AVURLAsset(url: source)
    let range = timeRange(options, duration: try await asset.load(.duration))
    let (type, ext) = videoContainer(of: source)
    let output = context.output(for: source, suffix: "trimmed", fileExtension: ext)
    try await export(
      asset, job: Job(preset: AVAssetExportPresetHighestQuality, fileType: type, timeRange: range),
      to: output, context: context)
    return output
  }

  static func trimAudio(_ source: URL, options: TransformOptions, context: TransformContext) async throws -> URL {
    try await exportAudio(source, suffix: "trimmed", range: options, context: context)
  }

  /// Re-times the video to `fps` and/or rotates it clockwise, through one video composition.
  static func recompose(
    _ source: URL, fps: Double?, rotation: Int, suffix: String, context: TransformContext
  ) async throws -> URL {
    let asset = AVURLAsset(url: source)
    guard let track = try await asset.loadTracks(withMediaType: .video).first else {
      throw TransformError.failed("This file has no video.")
    }
    let (natural, preferred, duration) = try await (
      track.load(.naturalSize), track.load(.preferredTransform), asset.load(.duration))
    let upright = natural.applying(preferred)
    let size = CGSize(width: abs(upright.width), height: abs(upright.height))
    let (transform, render) = VideoGeometry.rotated(
      preferred, size: size, degrees: rotation)
    let instruction = AVMutableVideoCompositionInstruction()
    instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
    let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
    layer.setTransform(transform, at: .zero)
    instruction.layerInstructions = [layer]
    let composition = AVMutableVideoComposition()
    composition.instructions = [instruction]
    composition.renderSize = render
    let nominal = try await track.load(.nominalFrameRate)
    composition.frameDuration = CMTime(seconds: 1 / (fps ?? Double(nominal > 0 ? nominal : 30)), preferredTimescale: 6000)
    let (type, ext) = videoContainer(of: source)
    let output = context.output(for: source, suffix: suffix, fileExtension: ext)
    try await export(
      asset,
      job: Job(preset: AVAssetExportPresetHighestQuality, fileType: type, videoComposition: composition),
      to: output, context: context)
    return output
  }

  // MARK: GIF

  static func makeGIF(fromVideo source: URL, options: TransformOptions, context: TransformContext) async throws -> URL {
    let asset = AVURLAsset(url: source)
    let duration = try await asset.load(.duration).seconds
    let plan = GIFTiming.plan(duration: duration, fps: options.gifFPS)
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.maximumSize = CGSize(width: options.gifWidth, height: options.gifWidth)
    let tolerance = CMTime(seconds: plan.delay / 2, preferredTimescale: 600)
    generator.requestedTimeToleranceBefore = tolerance
    generator.requestedTimeToleranceAfter = tolerance
    let times = plan.times.map { CMTime(seconds: $0, preferredTimescale: 600) }
    let output = context.output(for: source, suffix: "", fileExtension: "gif")
    let sink = try GIFSink(url: output, frameCount: times.count, delay: plan.delay)
    var written = 0
    for try await result in generator.images(for: times) {
      try context.checkCancelled()
      sink.add(try result.image)
      written += 1
      context.progress(Double(written) / Double(times.count))
    }
    try sink.finish()
    return output
  }

  static func makeGIF(fromImages sources: [URL], options: TransformOptions, context: TransformContext) throws -> URL {
    guard let first = sources.first else { throw TransformError.failed("Nothing to animate.") }
    let output = context.output(for: first, suffix: sources.count > 1 ? "animation" : "", fileExtension: "gif")
    let sink = try GIFSink(url: output, frameCount: sources.count, delay: max(0.02, options.gifImageDuration))
    var size: CGSize?
    for (index, source) in sources.enumerated() {
      try context.checkCancelled()
      let image = try ImageTransforms.decode(source, maxPixel: options.gifWidth)
      let target = size ?? CGSize(width: image.width, height: image.height)
      size = target
      let frame = ImageTransforms.redrawn(image, width: Int(target.width), height: Int(target.height), flattenOnWhite: true)
      sink.add(frame ?? image)
      context.progress(Double(index + 1) / Double(sources.count))
    }
    try sink.finish()
    return output
  }
}

/// Rotation math for video compositions (AVFoundation's render space is y-down).
enum VideoGeometry {
  /// `preferred` already makes the clip upright inside `size`; this adds a clockwise turn.
  static func rotated(_ preferred: CGAffineTransform, size: CGSize, degrees: Int) -> (CGAffineTransform, CGSize) {
    let turn = ((degrees % 360) + 360) % 360
    switch turn {
    case 90:
      return (preferred.concatenating(CGAffineTransform(rotationAngle: .pi / 2))
        .concatenating(CGAffineTransform(translationX: size.height, y: 0)), CGSize(width: size.height, height: size.width))
    case 180:
      return (preferred.concatenating(CGAffineTransform(rotationAngle: .pi))
        .concatenating(CGAffineTransform(translationX: size.width, y: size.height)), size)
    case 270:
      return (preferred.concatenating(CGAffineTransform(rotationAngle: 3 * .pi / 2))
        .concatenating(CGAffineTransform(translationX: 0, y: size.width)), CGSize(width: size.height, height: size.width))
    default:
      return (preferred, size)
    }
  }
}

/// Collects frames into an animated GIF on disk.
final class GIFSink {
  private let destination: CGImageDestination
  private let delay: Double
  private let url: URL

  init(url: URL, frameCount: Int, delay: Double) throws {
    guard let destination = CGImageDestinationCreateWithURL(
      url as CFURL, UTType.gif.identifier as CFString, max(1, frameCount), nil)
    else { throw TransformError.failed("Couldn’t create the GIF.") }
    self.destination = destination
    self.delay = delay
    self.url = url
    CGImageDestinationSetProperties(destination, [
      kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]
    ] as CFDictionary)
  }

  func add(_ image: CGImage) {
    CGImageDestinationAddImage(destination, image, [
      kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]
    ] as CFDictionary)
  }

  func finish() throws {
    guard CGImageDestinationFinalize(destination) else {
      try? FileManager.default.removeItem(at: url)
      throw TransformError.failed("Couldn’t write the GIF.")
    }
  }
}
