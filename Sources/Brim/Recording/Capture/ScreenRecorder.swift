// ScreenRecorder.swift
// Brim
//
// Owns one ScreenCaptureKit stream (video + optional system audio, cursor hidden) and, when asked,
// an AVCaptureSession for the microphone. Both stamp buffers with the host clock, which the
// writer and the pointer logger share.

import AVFoundation
import CoreMedia
import Foundation
import ScreenCaptureKit

enum HostClock {
    static func now() -> Double { CMClockGetTime(CMClockGetHostTimeClock()).seconds }
}

final class ScreenRecorder: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    struct Options: Sendable {
        var fps = 60
        var systemAudio = false
        var microphone = false
    }

    private let target: ResolvedRecordingTarget
    private let options: Options
    private let writer: RecordingWriter
    private let sampleQueue = DispatchQueue(label: "io.github.cezarprox.brim.recorder.samples", qos: .userInitiated)
    private var stream: SCStream?
    private var mic: MicrophoneCapture?
    /// Called (on any thread) if the stream dies, e.g. the recorded window closed.
    var onStreamStopped: (@Sendable (Error) -> Void)?

    init(target: ResolvedRecordingTarget, options: Options, outputURL: URL) throws {
        self.target = target
        self.options = options
        writer = try RecordingWriter(url: outputURL, pixelSize: target.pixelSize, fps: options.fps,
                                     systemAudio: options.systemAudio, microphone: options.microphone)
    }

    var clock: RecordingClock { writer.currentClock }

    static func configuration(for target: ResolvedRecordingTarget, options: Options) -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        config.width = Int(target.pixelSize.width)
        config.height = Int(target.pixelSize.height)
        if let rect = target.sourceRect { config.sourceRect = rect }
        config.scalesToFit = target.kind == .window
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(options.fps))
        config.queueDepth = 8
        config.showsCursor = false
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.colorSpaceName = CGColorSpace.sRGB
        config.capturesAudio = options.systemAudio
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 48_000
        config.channelCount = 2
        return config
    }

    func start() async throws {
        let stream = SCStream(filter: target.filter, configuration: Self.configuration(for: target, options: options), delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
        if options.systemAudio { try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue) }
        self.stream = stream
        if options.microphone {
            let mic = MicrophoneCapture { [writer] sample in writer.appendAudio(sample, from: .microphone) }
            try mic.start()
            self.mic = mic
        }
        do { try await stream.startCapture() } catch {
            mic?.stop()
            writer.cancel()
            throw ScreenCapturer.classifyCaptureError(error)
        }
    }

    func pause() { writer.pause(at: HostClock.now()) }
    func resume() { writer.resume(at: HostClock.now()) }

    func stop() async throws -> (duration: Double, clock: RecordingClock) {
        let end = HostClock.now()
        mic?.stop()
        try? await stream?.stopCapture()
        stream = nil
        return try await writer.finish(at: end)
    }

    func cancel() async {
        mic?.stop()
        try? await stream?.stopCapture()
        stream = nil
        writer.cancel()
    }

    // MARK: SCStreamOutput / SCStreamDelegate

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard sampleBuffer.isValid else { return }
        switch type {
        case .screen: writer.appendVideo(sampleBuffer)
        case .audio: writer.appendAudio(sampleBuffer, from: .system)
        default: break
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onStreamStopped?(error)
    }
}

/// The default microphone through AVCaptureSession, converted to 48 kHz mono 16-bit PCM.
final class MicrophoneCapture: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    enum MicrophoneError: LocalizedError {
        case unavailable

        var errorDescription: String? { L10n.tr("No microphone is available.") }
    }

    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "io.github.cezarprox.brim.recorder.mic", qos: .userInitiated)
    private let onSample: @Sendable (CMSampleBuffer) -> Void

    init(onSample: @escaping @Sendable (CMSampleBuffer) -> Void) {
        self.onSample = onSample
    }

    func start() throws {
        guard let device = AVCaptureDevice.default(for: .audio),
              let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else { throw MicrophoneError.unavailable }
        session.beginConfiguration()
        session.addInput(input)
        let output = AVCaptureAudioDataOutput()
        output.audioSettings = [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false,
        ]
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else { throw MicrophoneError.unavailable }
        session.addOutput(output)
        session.commitConfiguration()
        session.startRunning()
    }

    func stop() {
        if session.isRunning { session.stopRunning() }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        onSample(Self.onHostClock(sampleBuffer, from: session.synchronizationClock))
    }

    /// The session normally runs on the host clock already; if not, restamp so the writer can align it.
    private static func onHostClock(_ sample: CMSampleBuffer, from clock: CMClock?) -> CMSampleBuffer {
        let host = CMClockGetHostTimeClock()
        guard let clock, clock != host else { return sample }
        let pts = CMSampleBufferGetPresentationTimeStamp(sample)
        let converted = CMSyncConvertTime(pts, from: clock, to: host)
        guard pts.isValid, converted.isValid, abs((converted - pts).seconds) > 0.001 else { return sample }
        var timing = CMSampleTimingInfo(duration: CMSampleBufferGetDuration(sample), presentationTimeStamp: converted,
                                        decodeTimeStamp: .invalid)
        var copy: CMSampleBuffer?
        CMSampleBufferCreateCopyWithNewTiming(allocator: nil, sampleBuffer: sample, sampleTimingEntryCount: 1,
                                              sampleTimingArray: &timing, sampleBufferOut: &copy)
        return copy ?? sample
    }
}
