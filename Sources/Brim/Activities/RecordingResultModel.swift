import AppKit
import AVFoundation
import Combine
import Foundation

/// A finished native screen recording.
struct RecordingResult: Equatable, Identifiable {
    let id = UUID()
    let url: URL
    let duration: TimeInterval
    let bytes: Int64
    var thumbnail: NSImage?

    var sizeText: String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
    static func == (lhs: RecordingResult, rhs: RecordingResult) -> Bool { lhs.id == rhs.id }
}

/// Picks the recording file a native capture just wrote.
enum RecordingFileLocator {
    struct Candidate: Equatable {
        let url: URL
        let created: Date
        let bytes: Int64
    }

    static let extensions: Set<String> = ["mov", "mp4"]

    /// The newest video created at or after `since` (a little slack for clock rounding), not empty.
    static func pick(_ candidates: [Candidate], since: Date, slack: TimeInterval = 2) -> URL? {
        candidates
            .filter { extensions.contains($0.url.pathExtension.lowercased()) && $0.bytes > 0
                && $0.created >= since.addingTimeInterval(-slack) }
            .max { $0.created < $1.created }?.url
    }

    static func candidates(in folder: URL) -> [Candidate] {
        let keys: [URLResourceKey] = [.creationDateKey, .fileSizeKey]
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)), let created = values.creationDate else { return nil }
            return Candidate(url: url, created: created, bytes: Int64(values.fileSize ?? 0))
        }
    }

    /// Where macOS saves captures: the `com.apple.screencapture location` default, else the Desktop.
    static func captureFolder(defaultsLocation: String?) -> URL {
        if let path = defaultsLocation?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty {
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
        }
        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Desktop")
    }
}

/// Watches `ScreenRecordingModel`; when a recording stops it finds the saved file and publishes a
/// result card (thumbnail, Watch / Show in Finder / Copy / Trash), plus a HUD with Show in Finder.
@MainActor
final class RecordingResultModel: ObservableObject {
    static let shared = RecordingResultModel()
    @Published private(set) var result: RecordingResult?

    private let recording: ScreenRecordingModel
    private var cancellable: AnyCancellable?
    private var lastBegan: Date?
    private var dismissTask: Task<Void, Never>?

    init(recording: ScreenRecordingModel? = nil) { self.recording = recording ?? .shared }

    func start() {
        guard cancellable == nil else { return }
        cancellable = recording.$activeRecording.removeDuplicates().sink { [weak self] activity in
            Task { @MainActor in self?.changed(activity) }
        }
    }

    private func changed(_ activity: ScreenRecordingActivity?) {
        // Brim's own recordings open in Studio instead of the native result card.
        if let activity { lastBegan = activity.isInApp ? nil : activity.beganAt; return }
        guard let began = lastBegan, AppSettings.shared.recordingResultCard else { return }
        lastBegan = nil
        Task { await locate(since: began) }
    }

    private func locate(since began: Date) async {
        // The file is finalised a moment after the toolbar goes away.
        for _ in 0..<6 {
            try? await Task.sleep(for: .milliseconds(700))
            let folder = RecordingFileLocator.captureFolder(defaultsLocation: Self.defaultsLocation())
            let found = await Task.detached { RecordingFileLocator.pick(RecordingFileLocator.candidates(in: folder), since: began) }.value
            if let url = found { await publish(url, began: began); return }
        }
    }

    private func publish(_ url: URL, began: Date) async {
        let asset = AVURLAsset(url: url)
        let duration = (try? await asset.load(.duration).seconds) ?? 0
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        let thumbnail = await Self.thumbnail(asset)
        var next = RecordingResult(url: url, duration: duration.isFinite ? duration : 0, bytes: bytes)
        next.thumbnail = thumbnail
        result = next
        IslandFlashCenter.shared.show(
            "Recording saved", symbol: "record.circle.fill", tint: IslandTint.recording, duration: 6, kind: .general,
            detail: url.lastPathComponent, action: HUDAction(title: "Show in Finder", symbol: "magnifyingglass") {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }, secondaryAction: HUDAction(title: "Watch", symbol: "play.fill") { NSWorkspace.shared.open(url) },
            shortTitle: "Saved")
        LongTaskNotifier.shared.finished(
            title: "Screen recording saved", body: url.lastPathComponent, duration: Date.now.timeIntervalSince(began))
        scheduleDismiss(next.id)
    }

    func dismiss() { dismissTask?.cancel(); result = nil }

    private func scheduleDismiss(_ id: UUID) {
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(600))
            guard !Task.isCancelled, self?.result?.id == id else { return }
            self?.result = nil
        }
    }

    // MARK: Card actions

    func watch() { result.map { NSWorkspace.shared.open($0.url) } }
    func reveal() { result.map { NSWorkspace.shared.activateFileViewerSelecting([$0.url]) } }
    func openInStudio() {
        guard let url = result?.url else { return }
        Task { await StudioWindowController.open(videoAt: url) }
    }
    func share(from view: NSView) {
        guard let url = result?.url else { return }
        let picker = NSSharingServicePicker(items: [url])
        picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }
    func copy() {
        guard let url = result?.url else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([url as NSURL])
    }
    func trash() {
        guard let url = result?.url else { return }
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            result = nil
        } catch {
            IslandFlashCenter.shared.show("Couldn’t move to Trash", symbol: "exclamationmark.triangle.fill", tint: .red)
        }
    }

    private static func thumbnail(_ asset: AVURLAsset) async -> NSImage? {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 480, height: 300)
        guard let image = try? await generator.image(at: CMTime(seconds: 0.2, preferredTimescale: 600)).image else { return nil }
        return NSImage(cgImage: image, size: .zero)
    }

    private static func defaultsLocation() -> String? {
        UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location")
    }
}
