import AppKit
import Combine
import Foundation

/// What the compact island shows while a download runs.
struct DownloadSnapshot: Equatable {
    let name: String
    let bytes: Int64
    /// nil when the browser does not expose the total (Chrome, Firefox): the ring spins instead.
    let fraction: Double?
    let secondsLeft: TimeInterval?
    let count: Int

    var timeLeftText: String? { secondsLeft.map(DownloadETA.format) }
    /// Text beside the ring: time left, else the size so far.
    var trailingText: String {
        timeLeftText ?? ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

/// Watches ~/Downloads for partial files, estimates progress and time left, and announces completion
/// with Open / Show in Finder. Needs folder access, so it only runs when downloads are switched on.
@MainActor
final class DownloadProgressModel: ObservableObject {
    static let shared = DownloadProgressModel()
    @Published private(set) var active: DownloadSnapshot?

    private struct Tracked { var eta = DownloadETA(); var startedAt: Date; var last: DownloadEntry }
    private var tracked: [String: Tracked] = [:]
    private var primed = false
    private var timer: Timer?
    private let folder: () -> URL?
    private let flashes = IslandFlashCenter.shared

    init(folder: @escaping () -> URL? = { FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first }) {
        self.folder = folder
    }

    /// The first-run tour's sample download; the watcher never runs on such a model.
    func showPreview(_ snapshot: DownloadSnapshot?) { active = snapshot }

    /// Call from the settings refresh: starts or stops the 1 s watcher to match the settings.
    func refresh() {
        let settings = AppSettings.shared
        guard settings.downloadFlashesEnabled else { stop(); return }
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        timer?.tolerance = 0.3
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        tracked = [:]
        primed = false
        if active != nil { active = nil }
    }

    func poll(now: Date = .now) {
        guard let folder = folder() else { return }
        apply(DownloadScanner.scan(folder: folder), in: folder, now: now)
    }

    /// Core state update, separated from file access so tests can drive it.
    func apply(_ entries: [DownloadEntry], in folder: URL, now: Date) {
        let current = Dictionary(entries.map { ($0.partialName, $0) }, uniquingKeysWith: { first, _ in first })
        for (name, entry) in current {
            var item = tracked[name] ?? Tracked(startedAt: now, last: entry)
            item.eta.add(bytes: entry.bytes, at: now)
            item.last = entry
            if tracked[name] == nil, primed, !AppSettings.shared.downloadProgressRing {
                flashes.show("Downloading", symbol: "arrow.down.circle.fill", tint: .blue)
            }
            tracked[name] = item
        }
        for (name, item) in tracked where current[name] == nil {
            tracked[name] = nil
            if primed { finished(item, folder: folder, now: now) }
        }
        primed = true
        publish()
    }

    private func publish() {
        guard AppSettings.shared.downloadProgressRing,
              let lead = tracked.values.max(by: { $0.last.bytes < $1.last.bytes }) else {
            if active != nil { active = nil }
            return
        }
        let entry = lead.last
        let snapshot = DownloadSnapshot(
            name: entry.finalName, bytes: entry.bytes,
            fraction: DownloadETA.fraction(bytes: entry.bytes, total: entry.totalBytes),
            secondsLeft: lead.eta.secondsLeft(bytes: entry.bytes, total: entry.totalBytes), count: tracked.count)
        if snapshot != active { active = snapshot }
    }

    private func finished(_ item: Tracked, folder: URL, now: Date) {
        let target = folder.appendingPathComponent(item.last.finalName)
        guard FileManager.default.fileExists(atPath: target.path) else { return }
        flashes.show(
            item.last.finalName, symbol: "checkmark.circle.fill", tint: .blue, duration: 6, kind: .general,
            detail: "Downloaded", action: HUDAction(title: "Open", symbol: "arrow.up.forward.app") {
                NSWorkspace.shared.open(target)
            },
            secondaryAction: HUDAction(title: "Show in Finder", symbol: "magnifyingglass") {
                NSWorkspace.shared.activateFileViewerSelecting([target])
            }, shortTitle: "Downloaded")
        LongTaskNotifier.shared.finished(
            title: "Download finished", body: item.last.finalName, duration: now.timeIntervalSince(item.startedAt))
    }
}
