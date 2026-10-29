// StudioExporter.swift
// Brim
//
// Renders the edit to a file. Both formats read the composition through
// AVAssetReaderVideoCompositionOutput (so every frame passes the custom compositor); MP4 writes
// H.264/HEVC + AAC with AVAssetWriter, GIF writes frames with ImageIO.

import AVFoundation
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers
import VideoToolbox

final class StudioExporter: @unchecked Sendable {
    typealias Progress = @Sendable (Double) -> Void

    private let lock = NSLock()
    private var cancelled = false
    private var reader: AVAssetReader?

    func cancel() {
        let reader = lock.withLock { () -> AVAssetReader? in
            cancelled = true
            return self.reader
        }
        reader?.cancelReading()
    }

    private var isCancelled: Bool { lock.withLock { cancelled } }

    func export(asset: AVAsset, inputs: StudioRenderInputs, settings: ExportSettings, to url: URL,
                progress: @escaping Progress) async throws {
        let renderer = StudioFrameRenderer(inputs: inputs)
        let canvas = renderer.canvasSize(settings)
        let built = try await StudioCompositionBuilder.build(
            asset: asset, timeline: inputs.edit.timeline, renderer: renderer, renderSize: canvas, fps: settings.effectiveFPS)
        try? FileManager.default.removeItem(at: url)
        switch settings.format {
        case .mp4: try await writeMovie(built, canvas: canvas, settings: settings, to: url, progress: progress)
        case .gif: try await writeGIF(built, canvas: canvas, fps: settings.effectiveFPS, to: url, progress: progress)
        }
        if isCancelled {
            try? FileManager.default.removeItem(at: url)
            throw StudioExportError.cancelled
        }
        progress(1)
    }

    private func makeReader(_ built: StudioCompositionBuilder.Built, withAudio: Bool) async throws
        -> (AVAssetReader, AVAssetReaderVideoCompositionOutput, AVAssetReaderAudioMixOutput?) {
        let reader = try AVAssetReader(asset: built.composition)
        let videoTracks = try await built.composition.loadTracks(withMediaType: .video)
        let videoOutput = AVAssetReaderVideoCompositionOutput(videoTracks: videoTracks, videoSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
        ])
        videoOutput.videoComposition = built.videoComposition
        videoOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(videoOutput) else { throw StudioExportError.compositionFailed }
        reader.add(videoOutput)
        var audioOutput: AVAssetReaderAudioMixOutput?
        let audioTracks = try await built.composition.loadTracks(withMediaType: .audio)
        if withAudio, !audioTracks.isEmpty {
            let output = AVAssetReaderAudioMixOutput(audioTracks: audioTracks, audioSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 2,
                AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false,
            ])
            output.audioTimePitchAlgorithm = .spectral
            if reader.canAdd(output) { reader.add(output); audioOutput = output }
        }
        lock.withLock { self.reader = reader }
        return (reader, videoOutput, audioOutput)
    }

    // MARK: MP4

    private func writeMovie(_ built: StudioCompositionBuilder.Built, canvas: CGSize, settings: ExportSettings, to url: URL,
                            progress: @escaping Progress) async throws {
        let (reader, videoOutput, audioOutput) = try await makeReader(built, withAudio: true)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let pixels = Double(canvas.width * canvas.height)
        let bitrate = Int(pixels * Double(settings.fps) * (settings.codec == .hevc ? 0.07 : 0.1))
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: settings.codec == .hevc ? AVVideoCodecType.hevc : AVVideoCodecType.h264,
            AVVideoWidthKey: Int(canvas.width), AVVideoHeightKey: Int(canvas.height),
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: max(2_000_000, bitrate),
                                              AVVideoExpectedSourceFrameRateKey: settings.fps],
            AVVideoColorPropertiesKey: [AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                                        AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                                        AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2],
        ])
        videoInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(videoInput) else { throw StudioExportError.cannotWrite("video") }
        writer.add(videoInput)
        let audioInput: AVAssetWriterInput? = audioOutput == nil ? nil : {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 192_000,
            ])
            guard writer.canAdd(input) else { return nil }
            writer.add(input)
            return input
        }()
        guard reader.startReading() else { throw reader.error ?? StudioExportError.compositionFailed }
        guard writer.startWriting() else { throw writer.error ?? StudioExportError.cannotWrite("start") }
        writer.startSession(atSourceTime: .zero)
        let total = max(0.001, built.duration.seconds)

        let videoBox = StudioPumpBox(output: videoOutput, input: videoInput)
        let audioBox = audioOutput.flatMap { output in audioInput.map { StudioPumpBox(output: output, input: $0) } }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.pump(videoBox, label: "video") { time in progress(min(0.99, time / total)) } }
            if let audioBox { group.addTask { await self.pump(audioBox, label: "audio") { _ in } } }
        }

        if isCancelled || reader.status == .failed {
            writer.cancelWriting()
            if isCancelled { throw StudioExportError.cancelled }
            throw reader.error ?? StudioExportError.compositionFailed
        }
        await writer.finishWriting()
        if writer.status != .completed { throw writer.error ?? StudioExportError.cannotWrite("finish") }
    }

    /// Copies samples from a reader output into a writer input as fast as the input accepts them.
    private func pump(_ box: StudioPumpBox, label: String, onTime: @escaping @Sendable (Double) -> Void) async {
        let queue = DispatchQueue(label: "io.github.cezarprox.brim.studio.export.\(label)")
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            box.input.requestMediaDataWhenReady(on: queue) { [weak self] in
                while box.input.isReadyForMoreMediaData {
                    guard self?.isCancelled != true, let sample = box.output.copyNextSampleBuffer() else {
                        box.input.markAsFinished()
                        if box.finish() { continuation.resume() }
                        return
                    }
                    onTime(CMSampleBufferGetPresentationTimeStamp(sample).seconds)
                    if !box.input.append(sample) {
                        box.input.markAsFinished()
                        if box.finish() { continuation.resume() }
                        return
                    }
                }
            }
        }
    }

    // MARK: GIF

    private func writeGIF(_ built: StudioCompositionBuilder.Built, canvas: CGSize, fps: Int, to url: URL,
                          progress: @escaping Progress) async throws {
        let (reader, videoOutput, _) = try await makeReader(built, withAudio: false)
        let total = max(0.001, built.duration.seconds)
        let estimate = Int(total * Double(fps)) + 2
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, estimate, nil) else {
            throw StudioExportError.cannotWrite("gif")
        }
        CGImageDestinationSetProperties(destination, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0],
        ] as CFDictionary)
        let frameProperties = [kCGImagePropertyGIFDictionary: [
            kCGImagePropertyGIFDelayTime: 1.0 / Double(fps), kCGImagePropertyGIFUnclampedDelayTime: 1.0 / Double(fps),
        ]] as CFDictionary
        guard reader.startReading() else { throw reader.error ?? StudioExportError.compositionFailed }
        while !isCancelled, let sample = videoOutput.copyNextSampleBuffer() {
            autoreleasepool {
                guard let buffer = CMSampleBufferGetImageBuffer(sample) else { return }
                var image: CGImage?
                VTCreateCGImageFromCVPixelBuffer(buffer, options: nil, imageOut: &image)
                if let image { CGImageDestinationAddImage(destination, image, frameProperties) }
                progress(min(0.98, CMSampleBufferGetPresentationTimeStamp(sample).seconds / total))
            }
            await Task.yield()
        }
        if isCancelled { throw StudioExportError.cancelled }
        if reader.status == .failed { throw reader.error ?? StudioExportError.compositionFailed }
        guard CGImageDestinationFinalize(destination) else { throw StudioExportError.cannotWrite("gif") }
    }
}

/// Carries the non-Sendable AVFoundation pair into the writer's callback queue and makes sure the
/// continuation resumes once.
private final class StudioPumpBox: @unchecked Sendable {
    let output: AVAssetReaderOutput
    let input: AVAssetWriterInput
    private var done = false
    private let lock = NSLock()

    init(output: AVAssetReaderOutput, input: AVAssetWriterInput) {
        self.output = output
        self.input = input
    }

    func finish() -> Bool {
        lock.withLock {
            if done { return false }
            done = true
            return true
        }
    }
}
