// RecordingWriter.swift
// Brim
//
// Writes the raw capture (HEVC video + AAC system audio + AAC microphone) to the project's
// recording.mov. Every buffer arrives stamped with host time; `RecordingClock` subtracts paused
// time so the file plays continuously, and the same clock later aligns the pointer track.

import AVFoundation
import CoreMedia
import Foundation
import ScreenCaptureKit

enum RecordingAudioSource: Sendable { case system, microphone }

final class RecordingWriter: @unchecked Sendable {
    enum WriterError: LocalizedError {
        case cannotCreate(String)
        case noFrames

        var errorDescription: String? {
            switch self {
            case .cannotCreate(let detail): L10n.tr("The recording file could not be created.") + " " + detail
            case .noFrames: L10n.tr("Nothing was captured. Check Screen Recording access and try again.")
            }
        }
    }

    private let writer: AVAssetWriter
    private let video: AVAssetWriterInput
    private let systemAudio: AVAssetWriterInput?
    private let microphone: AVAssetWriterInput?
    private let lock = NSLock()
    private var clock = RecordingClock()
    private var lastVideoTime: CMTime = .invalid
    private var finished = false

    init(url: URL, pixelSize: CGSize, fps: Int, systemAudio: Bool, microphone: Bool) throws {
        try? FileManager.default.removeItem(at: url)
        do { writer = try AVAssetWriter(outputURL: url, fileType: .mov) } catch { throw WriterError.cannotCreate(error.localizedDescription) }
        let bitrate = Double(pixelSize.width * pixelSize.height) * Double(fps) * 0.08
        video = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: Int(pixelSize.width), AVVideoHeightKey: Int(pixelSize.height),
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: Int(min(max(bitrate, 6_000_000), 80_000_000)),
                                              AVVideoExpectedSourceFrameRateKey: fps,
                                              AVVideoAllowFrameReorderingKey: false],
            AVVideoColorPropertiesKey: [AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                                        AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                                        AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2],
        ])
        video.expectsMediaDataInRealTime = true
        guard writer.canAdd(video) else { throw WriterError.cannotCreate("video") }
        writer.add(video)
        let writer = self.writer
        func audioInput(channels: Int) -> AVAssetWriterInput? {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: channels,
                AVEncoderBitRateKey: channels == 1 ? 96_000 : 160_000,
            ])
            input.expectsMediaDataInRealTime = true
            guard writer.canAdd(input) else { return nil }
            writer.add(input)
            return input
        }
        self.systemAudio = systemAudio ? audioInput(channels: 2) : nil
        self.microphone = microphone ? audioInput(channels: 1) : nil
        guard writer.startWriting() else { throw WriterError.cannotCreate(writer.error?.localizedDescription ?? "") }
    }

    var currentClock: RecordingClock { lock.withLock { clock } }

    func appendVideo(_ sample: CMSampleBuffer) {
        lock.withLock {
            guard !finished, Self.isCompleteFrame(sample) else { return }
            let pts = CMSampleBufferGetPresentationTimeStamp(sample)
            guard pts.isValid, !clock.isInsidePause(pts.seconds) else { return }
            if clock.origin == nil {
                clock.begin(at: pts.seconds)
                writer.startSession(atSourceTime: pts)
            }
            guard let retimed = retime(sample, pts: pts), video.isReadyForMoreMediaData else { return }
            let time = CMSampleBufferGetPresentationTimeStamp(retimed)
            guard !lastVideoTime.isValid || time > lastVideoTime else { return }
            if video.append(retimed) { lastVideoTime = time }
        }
    }

    func appendAudio(_ sample: CMSampleBuffer, from source: RecordingAudioSource) {
        lock.withLock {
            guard !finished, let input = source == .system ? systemAudio : microphone else { return }
            let pts = CMSampleBufferGetPresentationTimeStamp(sample)
            guard let origin = clock.origin, pts.isValid, pts.seconds >= origin, !clock.isInsidePause(pts.seconds) else { return }
            guard let retimed = retime(sample, pts: pts), input.isReadyForMoreMediaData else { return }
            input.append(retimed)
        }
    }

    func pause(at host: Double) { lock.withLock { clock.pause(at: host) } }
    func resume(at host: Double) { lock.withLock { clock.resume(at: host) } }

    /// Closes the file. The last frame is held until `host` so a still ending isn't cut short.
    func finish(at host: Double) async throws -> (duration: Double, clock: RecordingClock) {
        let (endTime, finalClock): (CMTime?, RecordingClock) = lock.withLock {
            finished = true
            if clock.isPaused { clock.resume(at: host) }
            guard clock.origin != nil, lastVideoTime.isValid else { return (nil, clock) }
            let end = CMTime(seconds: host - clock.pausedDuration(before: host), preferredTimescale: 1_000_000_000)
            return (CMTimeMaximum(end, lastVideoTime), clock)
        }
        guard let endTime, let origin = finalClock.origin else {
            writer.cancelWriting()
            throw WriterError.noFrames
        }
        video.markAsFinished()
        systemAudio?.markAsFinished()
        microphone?.markAsFinished()
        writer.endSession(atSourceTime: endTime)
        await writer.finishWriting()
        if writer.status != .completed { throw WriterError.cannotCreate(writer.error?.localizedDescription ?? "") }
        return (endTime.seconds - origin, finalClock)
    }

    func cancel() {
        lock.withLock { finished = true }
        writer.cancelWriting()
    }

    /// Shifts a buffer back by the time spent paused before it.
    private func retime(_ sample: CMSampleBuffer, pts: CMTime) -> CMSampleBuffer? {
        let paused = clock.pausedDuration(before: pts.seconds)
        guard paused > 0 else { return sample }
        let offset = CMTime(seconds: paused, preferredTimescale: 1_000_000_000)
        var count: CMItemCount = 0
        CMSampleBufferGetSampleTimingInfoArray(sample, entryCount: 0, arrayToFill: nil, entriesNeededOut: &count)
        var timings = [CMSampleTimingInfo](repeating: CMSampleTimingInfo(), count: max(1, count))
        CMSampleBufferGetSampleTimingInfoArray(sample, entryCount: count, arrayToFill: &timings, entriesNeededOut: &count)
        for index in timings.indices {
            if timings[index].presentationTimeStamp.isValid { timings[index].presentationTimeStamp = timings[index].presentationTimeStamp - offset }
            if timings[index].decodeTimeStamp.isValid { timings[index].decodeTimeStamp = timings[index].decodeTimeStamp - offset }
        }
        var copy: CMSampleBuffer?
        CMSampleBufferCreateCopyWithNewTiming(allocator: nil, sampleBuffer: sample, sampleTimingEntryCount: timings.count,
                                              sampleTimingArray: &timings, sampleBufferOut: &copy)
        return copy
    }

    /// ScreenCaptureKit also delivers "idle" buffers with no pixels when nothing changed.
    static func isCompleteFrame(_ sample: CMSampleBuffer) -> Bool {
        guard CMSampleBufferGetImageBuffer(sample) != nil else { return false }
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int, let status = SCFrameStatus(rawValue: raw) else { return true }
        return status == .complete
    }
}
