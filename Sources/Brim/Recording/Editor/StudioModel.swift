// StudioModel.swift
// Brim
//
// State of one Studio editor window: the recording, the edit (with undo/redo and autosave), the
// playhead, the selection and the preview. Playback, editing and export live in extensions.

import AVFoundation
import Combine
import CoreGraphics
import Foundation

@MainActor
final class StudioModel: ObservableObject {
    enum Selection: Equatable {
        case clip(UUID)
        case zoom(UUID)
        case hidden(UUID)
    }

    enum Tool: Equatable { case crop, hide }

    enum ExportState: Equatable {
        case idle
        case running(format: ExportFormat, progress: Double)
        case finished(URL)
        case failed(String)
    }

    let project: RecordingProject?
    let metadata: RecordingMetadata
    let track: CursorTrack
    let asset: AVURLAsset
    let settings: AppSettings

    @Published var edit: StudioEdit {
        didSet { if edit != oldValue { editChanged(from: oldValue) } }
    }
    @Published var playhead: Double = 0
    @Published var isPlaying = false
    @Published var selection: Selection?
    @Published var tool: Tool?
    @Published var timelineZoom: Double = 1
    @Published var sidebarVisible = true
    @Published var exportSettings: ExportSettings { didSet { settings.studioExportSettings = exportSettings } }
    @Published var exportState: ExportState = .idle
    @Published var presets: [StudioStylePreset] { didSet { settings.studioPresets = presets } }
    @Published private(set) var preview: CGImage?
    /// The unstyled source frame at the playhead (crop and hide tools draw over it).
    @Published private(set) var rawFrame: CGImage?
    @Published private(set) var thumbnails: [(time: Double, image: CGImage)] = []
    @Published private(set) var history = EditHistory<StudioEdit>()

    private(set) var renderer: StudioFrameRenderer
    var lastCoalesceKey: String?
    var lastCoalesceTime = Date.distantPast
    var saveTask: Task<Void, Never>?
    var stillTask: Task<Void, Never>?
    var stillToken = 0
    var sourceFrames: [Int: CGImage] = [:]
    var playerRebuild: Task<Void, Never>?
    var timeObserver: Any?
    var exporter: StudioExporter?
    lazy var player: AVPlayer = {
        let player = AVPlayer()
        player.actionAtItemEnd = .pause
        return player
    }()

    init(project: RecordingProject?, metadata: RecordingMetadata, track: CursorTrack, edit: StudioEdit?, videoURL: URL,
         settings: AppSettings = .shared) {
        self.project = project
        self.metadata = metadata
        self.track = track
        self.settings = settings
        asset = AVURLAsset(url: videoURL)
        let initial = edit ?? StudioEdit.initial(duration: metadata.duration, track: track, style: settings.studioDefaultStyle)
        self.edit = initial
        exportSettings = settings.studioExportSettings
        presets = settings.studioPresets
        renderer = StudioFrameRenderer(inputs: StudioRenderInputs(edit: initial, metadata: metadata, track: track))
    }

    /// Opens a saved project.
    convenience init(project: RecordingProject, settings: AppSettings = .shared) throws {
        let metadata = try project.loadMetadata()
        self.init(project: project, metadata: metadata, track: project.loadTrack(), edit: project.loadEdit(),
                  videoURL: project.videoURL, settings: settings)
    }

    var title: String { metadata.title }
    var duration: Double { edit.timeline.duration }
    var sourceTime: Double { edit.timeline.sourceTime(forOutput: playhead) }

    /// Preview canvas: the export canvas' shape, capped for speed.
    var previewCanvas: CGSize {
        var settings = exportSettings
        settings.format = .mp4
        settings.resolution = .source
        let full = renderer.canvasSize(settings)
        let scale = min(1, 1600 / max(full.width, full.height))
        return CGSize(width: ExportGeometry.even(full.width * scale), height: ExportGeometry.even(full.height * scale))
    }

    // MARK: Changes

    /// Applies a change as one undo step. `coalesce` merges a run of changes with the same key
    /// (a slider drag) into a single step.
    func change(_ coalesce: String? = nil, _ body: (inout StudioEdit) -> Void) {
        var next = edit
        body(&next)
        guard next != edit else { return }
        let now = Date()
        let merges = coalesce != nil && coalesce == lastCoalesceKey && now.timeIntervalSince(lastCoalesceTime) < 0.8
        if !merges { history.record(edit) }
        lastCoalesceKey = coalesce
        lastCoalesceTime = now
        edit = next
    }

    func undo() {
        guard let previous = history.undo(current: edit) else { return }
        lastCoalesceKey = nil
        edit = previous
        validateSelection()
    }

    func redo() {
        guard let next = history.redo(current: edit) else { return }
        lastCoalesceKey = nil
        edit = next
        validateSelection()
    }

    private func editChanged(from old: StudioEdit) {
        renderer = StudioFrameRenderer(inputs: StudioRenderInputs(edit: edit, metadata: metadata, track: track), reusing: renderer)
        if playhead > duration { playhead = duration }
        refreshStill()
        if old.timeline != edit.timeline || isPlaying { schedulePlayerRebuild() }
        scheduleSave()
    }

    func validateSelection() {
        switch selection {
        case .clip(let id): if !edit.timeline.clips.contains(where: { $0.id == id }) { selection = nil }
        case .zoom(let id): if !edit.zooms.contains(where: { $0.id == id }) { selection = nil }
        case .hidden(let id): if !edit.hiddenAreas.contains(where: { $0.id == id }) { selection = nil }
        case nil: break
        }
    }

    private func scheduleSave() {
        guard let project else { return }
        saveTask?.cancel()
        let snapshot = edit
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            try? project.save(snapshot)
        }
    }

    func saveNow() {
        saveTask?.cancel()
        try? project?.save(edit)
    }

    // MARK: Presets

    func savePreset() {
        let name = L10n.tr("Preset") + " \(presets.count + 1)"
        presets.append(StudioStylePreset(name: name, style: edit.style))
        settings.studioDefaultStyle = edit.style
    }

    func apply(_ preset: StudioStylePreset) { change { $0.style = preset.style } }

    func deletePreset(_ preset: StudioStylePreset) { presets.removeAll { $0.id == preset.id } }

    func resetStyle() { change { $0.style = .standard } }

    // MARK: Still preview

    /// Re-renders the paused frame. Source frames are cached so style tweaks redraw instantly.
    func refreshStill() {
        let time = sourceTime
        let key = Int((time * 30).rounded())
        let renderer = renderer
        let canvas = previewCanvas
        stillToken += 1
        let token = stillToken
        stillTask?.cancel()
        let cached = sourceFrames[key]
        let asset = asset
        stillTask = Task { [weak self] in
            let frame: CGImage?
            if let cached { frame = cached } else { frame = await Self.sourceFrame(asset: asset, at: time) }
            guard let frame, !Task.isCancelled else { return }
            let image = await Task.detached(priority: .userInitiated) {
                renderer.stillImage(source: frame, sourceTime: time, canvas: canvas)
            }.value
            guard let self, token == self.stillToken else { return }
            if self.sourceFrames.count > 90 { self.sourceFrames.removeAll() }
            self.sourceFrames[key] = frame
            self.rawFrame = frame
            if let image { self.preview = image }
        }
    }

    static func sourceFrame(asset: AVAsset, at time: Double) async -> CGImage? {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(value: 1, timescale: 60)
        generator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 60)
        generator.maximumSize = CGSize(width: 2400, height: 2400)
        return try? await generator.image(at: CMTime(seconds: time, preferredTimescale: 600)).image
    }

    /// Filmstrip frames spread across the whole source.
    func loadThumbnails(count: Int = 28) {
        let asset = asset
        let duration = metadata.duration
        Task { [weak self] in
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 220, height: 220)
            generator.requestedTimeToleranceBefore = CMTime(value: 1, timescale: 4)
            generator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 4)
            let times = (0..<count).map { CMTime(seconds: duration * (Double($0) + 0.5) / Double(count), preferredTimescale: 600) }
            var frames: [(Double, CGImage)] = []
            for await result in generator.images(for: times) {
                if case .success(let requested, let image, _) = result { frames.append((requested.seconds, image)) }
            }
            self?.thumbnails = frames.sorted { $0.0 < $1.0 }.map { (time: $0.0, image: $0.1) }
        }
    }
}
