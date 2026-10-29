// StudioWindowController+Video.swift
// Brim
//
// Opens a video file that was not recorded by Brim (a native macOS screen recording) in
// Studio. There is no pointer track, so the editor offers trim, style and export.

import AVFoundation
import AppKit

extension StudioWindowController {
    /// Metadata read from the file itself, or nil when it holds no video.
    static func metadata(forVideoAt url: URL, scale: Double = Double(NSScreen.main?.backingScaleFactor ?? 2)) async -> RecordingMetadata? {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let natural = try? await track.load(.naturalSize),
              let transform = try? await track.load(.preferredTransform),
              let seconds = try? await asset.load(.duration).seconds, seconds.isFinite, seconds > 0
        else { return nil }
        let size = natural.applying(transform)
        let width = Int(abs(size.width).rounded()), height = Int(abs(size.height).rounded())
        guard width > 0, height > 0 else { return nil }
        let rate = (try? await track.load(.nominalFrameRate)).map { Int($0.rounded()) } ?? 60
        let hasAudio = ((try? await asset.loadTracks(withMediaType: .audio)) ?? []).isEmpty == false
        let created = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date()
        return RecordingMetadata(
            id: UUID(), createdAt: created, title: url.deletingPathExtension().lastPathComponent, source: .imported,
            pixelWidth: width, pixelHeight: height, pointWidth: Double(width) / scale, pointHeight: Double(height) / scale,
            fps: rate > 0 ? rate : 60, duration: seconds, hasSystemAudio: hasAudio, hasMicrophone: false)
    }

    /// "Open in Studio" for a plain video file.
    static func open(videoAt url: URL) async {
        guard let metadata = await metadata(forVideoAt: url) else {
            IslandFlashCenter.shared.show(L10n.tr("Couldn't open the recording"), symbol: "exclamationmark.triangle.fill", tint: .red)
            return
        }
        let model = StudioModel(project: nil, metadata: metadata, track: .empty, edit: nil, videoURL: url)
        let controller = StudioWindowController(model: model)
        open.append(controller)
        controller.present()
    }
}
