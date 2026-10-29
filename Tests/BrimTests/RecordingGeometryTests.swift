import CoreGraphics
import Foundation
import Testing

@testable import Brim

@Suite("Recording · export geometry")
struct RecordingGeometryTests {
    @Test func canvasFollowsResolutionAndAspect() {
        let retina = CGSize(width: 3024, height: 1964)
        #expect(ExportGeometry.canvasSize(content: retina, resolution: .source, aspect: .auto) == retina)
        let p1080 = ExportGeometry.canvasSize(content: retina, resolution: .p1080, aspect: .auto)
        #expect(p1080.height == 1080 && Int(p1080.width) % 2 == 0 && abs(p1080.width - 1662) <= 2)
        #expect(ExportGeometry.canvasSize(content: retina, resolution: .p720, aspect: .wide) == CGSize(width: 1280, height: 720))
        #expect(ExportGeometry.canvasSize(content: retina, resolution: .p1080, aspect: .vertical) == CGSize(width: 1080, height: 1920))
        #expect(ExportGeometry.canvasSize(content: retina, resolution: .p1080, aspect: .square) == CGSize(width: 1080, height: 1080))
        // Original size with a forced square aspect encloses the recording.
        #expect(ExportGeometry.canvasSize(content: CGSize(width: 1000, height: 500), resolution: .source, aspect: .square)
            == CGSize(width: 1000, height: 1000))
    }

    @Test func paddingCornersAndShadowScaleWithTheCanvas() {
        var style = RecordingStyle()
        style.padding = 0.1
        style.shadow = 1
        style.corners = .large
        let layout = ExportGeometry.layout(canvas: CGSize(width: 1920, height: 1080), content: CGSize(width: 1600, height: 900), style: style)
        // 10% of the short side (108 px) each side, then 16:9 fits the 1704×864 box by height.
        #expect(abs(layout.videoRect.height - 864) < 0.01)
        #expect(abs(layout.videoRect.width - 1536) < 0.01)
        #expect(abs(layout.videoRect.midX - 960) < 0.01 && abs(layout.videoRect.midY - 540) < 0.01)
        #expect(abs(layout.cornerRadius - 0.05 * 864) < 0.01)
        #expect(layout.shadowOpacity == 0.75)
        style.padding = 0; style.shadow = 0; style.corners = .square
        let bare = ExportGeometry.layout(canvas: CGSize(width: 1600, height: 900), content: CGSize(width: 1600, height: 900), style: style)
        #expect(bare.videoRect == CGRect(x: 0, y: 0, width: 1600, height: 900))
        #expect(bare.cornerRadius == 0 && bare.shadowRadius == 0)
    }

    @Test func cameraMapsSourcePointsOntoTheFrame() {
        let layout = ExportGeometry.layout(canvas: CGSize(width: 1000, height: 500), content: CGSize(width: 1000, height: 500),
                                           style: RecordingStyle(background: .gradient(0), padding: 0, shadow: 0, corners: .square))
        let identity = ExportGeometry.canvasPoint(CGPoint(x: 0.25, y: 0.5), layout: layout, camera: .identity)
        #expect(identity == CGPoint(x: 250, y: 250))
        let zoomed = CameraState(scale: 2, center: CGPoint(x: 0.25, y: 0.25))
        // The zoom centre lands in the middle of the frame and distances double.
        #expect(ExportGeometry.canvasPoint(CGPoint(x: 0.25, y: 0.25), layout: layout, camera: zoomed) == CGPoint(x: 500, y: 250))
        #expect(ExportGeometry.canvasPoint(CGPoint(x: 0.3, y: 0.25), layout: layout, camera: zoomed).x == 600)
        #expect(ExportGeometry.pointScale(layout: layout, contentPoints: CGSize(width: 500, height: 250), camera: zoomed) == 4)
    }

    @Test func cropRemapsNormalisedPoints() {
        let crop = CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5)
        #expect(ExportGeometry.cropped(CGPoint(x: 0.75, y: 0.25), crop: crop) == CGPoint(x: 0.5, y: 0.5))
        let clamped = StudioEdit.clampedCrop(CGRect(x: 0.9, y: -0.2, width: 0.5, height: 0.01))
        #expect(clamped.maxX <= 1 && clamped.minY == 0 && clamped.height == 0.05)
    }

    @Test func gifCapsResolution() {
        var settings = ExportSettings()
        settings.format = .gif
        #expect(settings.effectiveResolution == .p720)
        #expect(settings.effectiveFPS == 15)
        settings.resolution = .p480
        #expect(settings.effectiveResolution == .p480)
    }
}

@Suite("Recording · project persistence")
struct RecordingProjectTests {
    @Test func projectRoundTrips() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("qs-rec-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let project = try RecordingProject.create(in: root)
        let metadata = RecordingMetadata(
            id: UUID(), createdAt: Date(timeIntervalSince1970: 1_800_000_000), title: "Demo", source: .area,
            pixelWidth: 2880, pixelHeight: 1800, pointWidth: 1440, pointHeight: 900, fps: 60, duration: 6,
            hasSystemAudio: true, hasMicrophone: false)
        let track = CursorTrack(samples: [CursorSample(t: 0, x: 0.1, y: 0.2)], clicks: [CursorClick(t: 1, x: 0.5, y: 0.5, button: 0, up: 1.1)])
        var edit = StudioEdit.initial(duration: 6, track: track)
        edit.timeline.split(atOutput: 3)
        edit.hiddenAreas = [HiddenArea(rect: CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.1), start: 1, end: 2, kind: .pixelate)]
        edit.style.background = .solid(StudioRGB(hex: 0x112233))
        edit.style.corners = .large
        edit.crop = CGRect(x: 0.1, y: 0, width: 0.8, height: 1)
        try project.save(metadata)
        try project.save(track)
        try project.save(edit)

        let reopened = RecordingProject(folder: project.folder)
        #expect(try reopened.loadMetadata() == metadata)
        #expect(reopened.loadTrack() == track)
        #expect(reopened.loadEdit() == edit)
        #expect(edit.zooms.count == 1)
        #expect(metadata.pixelsPerPoint == 2)
        let listed = RecordingLibrary.projects(in: root)
        #expect(listed.count == 1 && listed[0].1.title == "Demo")
    }

    @Test func missingTrackIsNotFatal() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("qs-rec-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let project = try RecordingProject.create(in: root)
        #expect(project.loadTrack() == .empty)
        #expect(project.loadEdit() == nil)
        #expect(throws: (any Error).self) { try project.loadMetadata() }
    }
}
