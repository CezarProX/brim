// StudioCompositor.swift
// Brim
//
// The AVVideoCompositing implementation behind both the editor's live preview and the export:
// AVFoundation hands it each source frame at a composition (output) time; it maps that to source
// time through the cut list and asks `StudioFrameRenderer` to draw the styled frame.

import AVFoundation
import CoreImage
import Foundation

/// One instruction covering the whole edited video; it carries the renderer and the cut list.
final class StudioCompositionInstruction: NSObject, AVVideoCompositionInstructionProtocol, @unchecked Sendable {
    let timeRange: CMTimeRange
    let enablePostProcessing = false
    let containsTweening = true
    let requiredSourceTrackIDs: [NSValue]?
    let passthroughTrackID = kCMPersistentTrackID_Invalid
    let renderer: StudioFrameRenderer
    let timeline: EditTimeline
    let sourceTrackID: CMPersistentTrackID

    init(timeRange: CMTimeRange, trackID: CMPersistentTrackID, renderer: StudioFrameRenderer, timeline: EditTimeline) {
        self.timeRange = timeRange
        sourceTrackID = trackID
        requiredSourceTrackIDs = [NSNumber(value: trackID)]
        self.renderer = renderer
        self.timeline = timeline
    }
}

final class StudioCompositor: NSObject, AVVideoCompositing, @unchecked Sendable {
    private static let pixelFormat = Int(kCVPixelFormatType_32BGRA)
    private let queue = DispatchQueue(label: "io.github.cezarprox.brim.studio.compositor", qos: .userInitiated)

    let sourcePixelBufferAttributes: [String: any Sendable]? = [
        kCVPixelBufferPixelFormatTypeKey as String: pixelFormat,
        kCVPixelBufferIOSurfacePropertiesKey as String: [String: any Sendable](),
    ]
    let requiredPixelBufferAttributesForRenderContext: [String: any Sendable] = [
        kCVPixelBufferPixelFormatTypeKey as String: pixelFormat,
        kCVPixelBufferIOSurfacePropertiesKey as String: [String: any Sendable](),
    ]

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {}

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        queue.async {
            autoreleasepool {
                guard let instruction = request.videoCompositionInstruction as? StudioCompositionInstruction else {
                    request.finish(with: StudioExportError.compositionFailed)
                    return
                }
                guard let source = request.sourceFrame(byTrackID: instruction.sourceTrackID),
                      let output = request.renderContext.newPixelBuffer() else {
                    request.finish(with: StudioExportError.compositionFailed)
                    return
                }
                let sourceTime = instruction.timeline.sourceTime(forOutput: request.compositionTime.seconds)
                instruction.renderer.render(source: CIImage(cvPixelBuffer: source), sourceTime: sourceTime, into: output)
                request.finish(withComposedVideoFrame: output)
            }
        }
    }

    func cancelAllPendingVideoCompositionRequests() {
        queue.sync {}
    }
}

enum StudioExportError: LocalizedError, Equatable {
    case noVideoTrack
    case compositionFailed
    case cannotWrite(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .noVideoTrack: L10n.tr("The recording has no video to export.")
        case .compositionFailed: L10n.tr("A frame of the recording could not be drawn.")
        case .cannotWrite(let detail): L10n.tr("The export could not be written.") + " " + detail
        case .cancelled: L10n.tr("Export cancelled.")
        }
    }
}

/// Builds the edited asset: clips laid end to end with their speeds, plus a video composition that
/// routes every frame through `StudioCompositor`.
enum StudioCompositionBuilder {
    struct Built {
        let composition: AVMutableComposition
        let videoComposition: AVMutableVideoComposition
        let duration: CMTime
    }

    static let timescale: CMTimeScale = 600

    static func build(asset: AVAsset, timeline: EditTimeline, renderer: StudioFrameRenderer,
                      renderSize: CGSize, fps: Int) async throws -> Built {
        guard let sourceVideo = try await asset.loadTracks(withMediaType: .video).first else { throw StudioExportError.noVideoTrack }
        let sourceAudio = try await asset.loadTracks(withMediaType: .audio)
        let composition = AVMutableComposition()
        guard let video = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw StudioExportError.compositionFailed
        }
        let audio = sourceAudio.compactMap { _ in
            composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        }
        let assetDuration = try await asset.load(.duration)
        var cursor = CMTime.zero
        for clip in timeline.clips {
            let start = CMTime(seconds: clip.sourceStart, preferredTimescale: timescale)
            let end = CMTimeMinimum(CMTime(seconds: clip.sourceEnd, preferredTimescale: timescale), assetDuration)
            guard end > start else { continue }
            let range = CMTimeRange(start: start, end: end)
            try video.insertTimeRange(range, of: sourceVideo, at: cursor)
            for (track, source) in zip(audio, sourceAudio) {
                let sourceRange = try await source.load(.timeRange)
                let clipped = range.intersection(sourceRange)
                guard clipped.duration > .zero else { continue }
                try track.insertTimeRange(clipped, of: source, at: cursor + (clipped.start - range.start))
            }
            let inserted = CMTimeRange(start: cursor, duration: range.duration)
            if abs(clip.speed - 1) > 0.001 {
                let scaled = CMTime(seconds: range.duration.seconds / clip.speed, preferredTimescale: timescale)
                composition.scaleTimeRange(inserted, toDuration: scaled)
                cursor = cursor + scaled
            } else {
                cursor = cursor + range.duration
            }
        }
        let videoComposition = AVMutableVideoComposition()
        videoComposition.customVideoCompositorClass = StudioCompositor.self
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(max(1, fps)))
        videoComposition.instructions = [StudioCompositionInstruction(
            timeRange: CMTimeRange(start: .zero, duration: cursor), trackID: video.trackID, renderer: renderer, timeline: timeline)]
        return Built(composition: composition, videoComposition: videoComposition, duration: cursor)
    }
}
