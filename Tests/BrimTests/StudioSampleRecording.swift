import AVFoundation
import CoreGraphics
import Foundation

@testable import Brim

/// Writes a small synthetic "screen recording" project: a fake app window whose button lights up
/// when clicked, plus a matching pointer track, so the editor and exporter have real media.
enum StudioSampleRecording {
    static let size = CGSize(width: 1440, height: 900)
    static let duration = 6.0
    static let fps = 30

    /// Pointer path: glide to the button, click, wander to the list, click again.
    static let track: CursorTrack = {
        var samples: [CursorSample] = []
        let keyframes: [(Double, Double, Double)] = [
            (0, 0.30, 0.70), (1.2, 0.62, 0.36), (2.0, 0.66, 0.33), (2.6, 0.66, 0.33),
            (3.4, 0.35, 0.55), (4.0, 0.33, 0.58), (5.0, 0.33, 0.58), (6.0, 0.48, 0.62),
        ]
        for frame in 0...Int(duration * 60) {
            let t = Double(frame) / 60
            guard let upper = keyframes.firstIndex(where: { $0.0 >= t }), upper > 0 else {
                samples.append(CursorSample(t: t, x: keyframes[0].1, y: keyframes[0].2)); continue
            }
            let a = keyframes[upper - 1], b = keyframes[upper]
            let f = (t - a.0) / (b.0 - a.0)
            let eased = f * f * (3 - 2 * f)
            samples.append(CursorSample(t: t, x: a.1 + (b.1 - a.1) * eased, y: a.2 + (b.2 - a.2) * eased))
        }
        let clicks = [CursorClick(t: 2.1, x: 0.66, y: 0.33, button: 0, up: 2.22),
                      CursorClick(t: 4.1, x: 0.33, y: 0.58, button: 0, up: 4.2)]
        return CursorTrack(samples: samples, clicks: clicks)
    }()

    static func makeProject(in root: URL) async throws -> RecordingProject {
        let project = try RecordingProject.create(in: root)
        try await writeVideo(to: project.videoURL)
        let metadata = RecordingMetadata(
            id: UUID(), createdAt: Date(), title: "Demo", source: .area, pixelWidth: Int(size.width), pixelHeight: Int(size.height),
            pointWidth: size.width / 2, pointHeight: size.height / 2, fps: fps, duration: duration, hasSystemAudio: false, hasMicrophone: false)
        try project.save(metadata)
        try project.save(track)
        try project.save(StudioEdit.initial(duration: duration, track: track))
        return project
    }

    static func writeVideo(to url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: Int(size.width), AVVideoHeightKey: Int(size.height),
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferWidthKey as String: Int(size.width), kCVPixelBufferHeightKey as String: Int(size.height),
        ])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        let frames = Int(duration * Double(fps))
        for frame in 0..<frames {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(2)) }
            guard let pool = adaptor.pixelBufferPool else { break }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            guard let buffer else { continue }
            draw(into: buffer, t: Double(frame) / Double(fps))
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(fps)))
        }
        input.markAsFinished()
        await writer.finishWriting()
    }

    /// A light "app": toolbar, sidebar, cards and a button that turns blue after the click.
    private static func draw(into buffer: CVPixelBuffer, t: Double) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer), width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else { return }
        // Flip to a top-left origin so the layout reads like the screen.
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)
        func fill(_ rect: CGRect, _ gray: Double, radius: Double = 0, alpha: Double = 1) {
            context.setFillColor(CGColor(gray: gray, alpha: alpha))
            context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
            context.fillPath()
        }
        fill(CGRect(origin: .zero, size: size), 0.97)
        fill(CGRect(x: 0, y: 0, width: size.width, height: 64), 0.93)
        for (i, color) in [(1.0, 0.37, 0.34), (1.0, 0.74, 0.18), (0.16, 0.79, 0.25)].enumerated() {
            context.setFillColor(CGColor(srgbRed: color.0, green: color.1, blue: color.2, alpha: 1))
            context.fillEllipse(in: CGRect(x: Double(24 + i * 30), y: 24, width: 16, height: 16))
        }
        fill(CGRect(x: 0, y: 64, width: 280, height: size.height - 64), 0.94)
        for row in 0..<9 {
            let selected = t > 4.1 && row == 3
            if selected { context.setFillColor(CGColor(srgbRed: 0.2, green: 0.47, blue: 1, alpha: 1)) }
            else { context.setFillColor(CGColor(gray: 0.82, alpha: 1)) }
            let rowRect = CGRect(x: 24, y: Double(104 + row * 52), width: Double(220 - (row % 3) * 30), height: 22)
            context.addPath(CGPath(roundedRect: rowRect,
                                   cornerWidth: 8, cornerHeight: 8, transform: nil))
            context.fillPath()
        }
        for card in 0..<3 {
            let rect = CGRect(x: Double(330 + card * 360), y: 120, width: 330, height: 200)
            fill(rect, 1, radius: 18)
            fill(CGRect(x: rect.minX + 24, y: rect.minY + 28, width: 180, height: 18), 0.8, radius: 6)
            fill(CGRect(x: rect.minX + 24, y: rect.minY + 62, width: 260, height: 12), 0.88, radius: 5)
            fill(CGRect(x: rect.minX + 24, y: rect.minY + 84, width: 220, height: 12), 0.88, radius: 5)
        }
        let pressed = t > 2.1
        context.setFillColor(pressed ? CGColor(srgbRed: 0.2, green: 0.47, blue: 1, alpha: 1) : CGColor(gray: 0.78, alpha: 1))
        context.addPath(CGPath(roundedRect: CGRect(x: 0.66 * size.width - 90, y: 0.33 * size.height - 26, width: 180, height: 52),
                               cornerWidth: 26, cornerHeight: 26, transform: nil))
        context.fillPath()
        // A progress bar that fills over time, so frames differ.
        fill(CGRect(x: 330, y: 380, width: 1050, height: 14), 0.88, radius: 7)
        context.setFillColor(CGColor(srgbRed: 0.2, green: 0.47, blue: 1, alpha: 1))
        context.addPath(CGPath(roundedRect: CGRect(x: 330, y: 380, width: 1050 * t / duration, height: 14), cornerWidth: 7, cornerHeight: 7, transform: nil))
        context.fillPath()
        for line in 0..<6 {
            let y = Double(440 + line * 56)
            let width = 1050 - Double(line % 4) * 140
            fill(CGRect(x: 330, y: y, width: width, height: 26), 0.91, radius: 8)
        }
    }
}
