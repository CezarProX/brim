import AppKit
import AVFoundation
import CoreGraphics
import ImageIO
import SwiftUI
import Testing

@testable import Brim

@Suite("Recording · Studio render and export", .serialized)
@MainActor
struct StudioRenderTests {
    private static func tempRoot() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("qs-studio-\(UUID().uuidString)")
    }

    private static func waitFor(_ condition: () -> Bool, seconds: Double = 8) async {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition(), Date() < deadline { try? await Task.sleep(for: .milliseconds(50)) }
    }

    private static func savePNG(_ image: CGImage, _ name: String) throws {
        let url = try DropletRender.url(name)
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
    }

    @Test func rendererDrawsStyledZoomedFrameWithPointer() async throws {
        let root = Self.tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let project = try await StudioSampleRecording.makeProject(in: root)
        let model = try StudioModel(project: project, settings: DropletRender.isolatedSettings())
        let frame = try #require(await StudioModel.sourceFrame(asset: model.asset, at: 2.2))
        let renderer = StudioFrameRenderer(inputs: StudioRenderInputs(edit: model.edit, metadata: model.metadata, track: model.track))
        let canvas = CGSize(width: 1600, height: 1000)
        let still = try #require(renderer.stillImage(source: frame, sourceTime: 2.2, canvas: canvas))
        #expect(still.width == 1600 && still.height == 1000)
        #expect(renderer.cameraState(at: 2.2).scale > 1.5)  // auto zoom on the first click
        try Self.savePNG(still, "studio-frame-zoomed.png")
        let wide = try #require(renderer.stillImage(source: frame, sourceTime: 0.3, canvas: canvas))
        try Self.savePNG(wide, "studio-frame-wide.png")
    }

    @Test func editorWindowRenders() async throws {
        let root = Self.tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let project = try await StudioSampleRecording.makeProject(in: root)
        let model = try StudioModel(project: project, settings: DropletRender.isolatedSettings())
        model.edit.timeline.split(atOutput: 4.4)
        model.edit.timeline.setSpeed(1.5, clip: model.edit.timeline.clips[1].id)
        model.selection = .zoom(try #require(model.edit.zooms.first?.id))
        model.loadThumbnails()
        model.seek(to: 3.0)
        await Self.waitFor { model.preview != nil && !model.thumbnails.isEmpty }
        #expect(model.preview != nil)
        let view = StudioView(model: model)
        try await DropletRender.png(view, size: CGSize(width: 1280, height: 820), name: "studio-editor.png", background: StudioTheme.window)
        model.selection = .clip(model.edit.timeline.clips[1].id)
        model.edit.style.background = .gradient(5)
        model.edit.style.corners = .large
        model.edit.style.padding = 0.1
        await Self.waitFor({ false }, seconds: 0.6)
        try await DropletRender.png(view, size: CGSize(width: 1280, height: 820), name: "studio-editor-clip.png", background: StudioTheme.window)
    }

    @Test func exportsMP4AndGIFThroughTheCompositor() async throws {
        let root = Self.tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let project = try await StudioSampleRecording.makeProject(in: root)
        let model = try StudioModel(project: project, settings: DropletRender.isolatedSettings())
        var edit = model.edit
        edit.timeline.split(atOutput: 3)
        edit.timeline.setSpeed(2, clip: edit.timeline.clips[1].id)  // 3 s + 1.5 s
        let inputs = StudioRenderInputs(edit: edit, metadata: model.metadata, track: model.track)
        var settings = ExportSettings()
        settings.resolution = .p720
        settings.fps = 30
        let movie = root.appendingPathComponent("out.mp4")
        try await StudioExporter().export(asset: model.asset, inputs: inputs, settings: settings, to: movie) { _ in }
        let asset = AVURLAsset(url: movie)
        let duration = try await asset.load(.duration).seconds
        #expect(abs(duration - 4.5) < 0.15)
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let size = try await track.load(.naturalSize)
        #expect(size.height == 720 && size.width == 1152)

        settings.format = .gif
        settings.resolution = .p480
        settings.gifFPS = 10
        let gif = root.appendingPathComponent("out.gif")
        try await StudioExporter().export(asset: model.asset, inputs: inputs, settings: settings, to: gif) { _ in }
        let source = try #require(CGImageSourceCreateWithURL(gif as CFURL, nil))
        #expect(abs(CGImageSourceGetCount(source) - 45) <= 2)
        let first = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(first.height == 480)
    }

    @Test(.enabled(if: CGPreflightScreenCaptureAccess(), "needs Screen Recording permission for the test runner"))
    func recordsTheDisplayLiveThenExports() async throws {
        let root = Self.tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let project = try RecordingProject.create(in: root)
        let target = try await RecordingSourceResolver.resolve(.display(CGMainDisplayID()), retina: false)
        let recorder = try ScreenRecorder(target: target, options: .init(fps: 30), outputURL: project.videoURL)
        try await recorder.start()
        try await Task.sleep(for: .milliseconds(2300))
        let (duration, clock) = try await recorder.stop()
        #expect(clock.origin != nil)
        #expect(duration > 1.8 && duration < 3)
        let asset = AVURLAsset(url: project.videoURL)
        #expect(abs(try await asset.load(.duration).seconds - duration) < 0.2)
        let metadata = RecordingMetadata(
            id: UUID(), createdAt: Date(), title: "Live", source: .display, pixelWidth: Int(target.pixelSize.width),
            pixelHeight: Int(target.pixelSize.height), pointWidth: target.pointSize.width, pointHeight: target.pointSize.height,
            fps: 30, duration: duration, hasSystemAudio: false, hasMicrophone: false)
        var settings = ExportSettings()
        settings.resolution = .p480
        let out = root.appendingPathComponent("live.mp4")
        try await StudioExporter().export(asset: asset, inputs: StudioRenderInputs(edit: StudioEdit(sourceDuration: duration), metadata: metadata,
                                                                                   track: .empty), settings: settings, to: out) { _ in }
        #expect(abs(try await AVURLAsset(url: out).load(.duration).seconds - duration) < 0.2)
    }
}

@Suite("Recording · recorder chrome renders")
@MainActor
struct RecorderChromeRenderTests {
    @Test func recorderBarRenders() async throws {
        let model = RecordingBarModel(settings: DropletRender.isolatedSettings())
        model.microphone = true
        try await DropletRender.png(RecordingBarView(model: model).padding(20), size: CGSize(width: 560, height: 100),
                                    name: "recording-bar.png", background: Color(white: 0.45))
        model.select(.area)
        try await DropletRender.png(RecordingBarView(model: model).padding(20), size: CGSize(width: 560, height: 100),
                                    name: "recording-bar-area.png", background: Color(white: 0.45))
    }

    @Test func islandShowsInAppRecordingWithPause() async throws {
        let model = ScreenRecordingModel(probe: { nil })
        model.showInAppRecording(ScreenRecordingActivity(beganAt: Date().addingTimeInterval(-75), isInApp: true),
                                 handlers: .init(stop: {}, togglePause: {}))
        #expect(model.supportsPause)
        #expect(model.activeRecording?.isInApp == true)
        await model.refreshNow()  // the system probe must not clear our own recording
        #expect(model.activeRecording != nil)
        let view = ScreenRecordingActivityView(model: model).padding(16).background(Color.black)
        try await DropletRender.png(view, size: CGSize(width: 420, height: 90), name: "recording-island-live.png", background: .black)
        model.showInAppRecording(ScreenRecordingActivity(beganAt: Date().addingTimeInterval(-75), isInApp: true, pausedElapsed: 75),
                                 handlers: .init(stop: {}, togglePause: {}))
        try await DropletRender.png(view, size: CGSize(width: 420, height: 90), name: "recording-island-paused.png", background: .black)
        model.endInAppRecording()
        #expect(model.activeRecording == nil && !model.supportsPause)
    }
}
