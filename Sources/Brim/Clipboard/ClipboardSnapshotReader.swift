import AppKit

/// What one copy contained, read off the main thread and already bounded in size.
enum ClipboardSnapshot: Sendable, Equatable {
    case files(String)
    case image(Data)
    case color(String)
    case text(String)
}

/// `NSPasteboard` is a reference type without Sendable annotations; reads are only ever made
/// from one background block at a time, so handing it across is safe.
struct ClipboardPasteboardBox: @unchecked Sendable {
    let pasteboard: NSPasteboard
}

/// Reads the pasteboard where content may be handed over lazily (promised types, big images,
/// file promises). Those reads block until the source app answers, so they never run on the main
/// thread, and `read(timeout:)` gives up on a source that stays silent.
struct ClipboardSnapshotReader: Sendable {
    let maxImageBytes: Int
    let maxTextBytes: Int

    /// Blocking read; call from a background queue. Nil when nothing usable or over the limits.
    func read(_ box: ClipboardPasteboardBox) -> ClipboardSnapshot? {
        let pasteboard = box.pasteboard
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self],
                                             options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            // Finder also offers an icon image for copied files; the files are what matters.
            let paths = urls.prefix(50).map(\.standardizedFileURL.path).joined(separator: "\n")
            return paths.utf8.count <= maxTextBytes ? .files(paths) : nil
        }
        if let type = pasteboard.availableType(from: [.png, .tiff]), let data = pasteboard.data(forType: type) {
            return data.count <= maxImageBytes ? .image(data) : nil
        }
        if pasteboard.availableType(from: [.color]) != nil,
           let color = NSColor(from: pasteboard), let hex = ClipboardEntry.hex(color) {
            return .color(hex)
        }
        if let text = pasteboard.string(forType: .string) ?? pasteboard.string(forType: .URL) {
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  text.utf8.count <= maxTextBytes else { return nil }
            return .text(text)
        }
        return nil
    }

    /// Runs `work` on a background queue and returns its result, or nil once `timeout` passes.
    /// A read that never returns keeps its own thread, but the caller is released on time.
    static func run(timeout: TimeInterval,
                    _ work: @escaping @Sendable () -> ClipboardSnapshot?) async -> ClipboardSnapshot? {
        await withCheckedContinuation { continuation in
            let gate = ResumeOnce(continuation)
            DispatchQueue.global(qos: .utility).async { gate.resume(work()) }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + max(0, timeout)) { gate.resume(nil) }
        }
    }
}

private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<ClipboardSnapshot?, Never>?
    init(_ continuation: CheckedContinuation<ClipboardSnapshot?, Never>) { self.continuation = continuation }
    func resume(_ value: ClipboardSnapshot?) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: value)
    }
}
