// ClipboardAutoClear.swift
// Brim
//
// Empties the Mac clipboard a while after something was copied, without touching
// the history. Only clears if nothing else has been copied in the meantime.

import AppKit

@MainActor
final class ClipboardAutoClear {
    private var task: Task<Void, Never>?

    /// Whether a copy should be scheduled for clearing under the given settings.
    nonisolated static func shouldSchedule(seconds: Int, onlySensitive: Bool, sensitive: Bool) -> Bool {
        seconds > 0 && (!onlySensitive || sensitive)
    }

    /// Schedules `pasteboard` to be cleared after `seconds` if its change count is still `changeCount`.
    /// `onCleared` receives the pasteboard's new change count so the caller can ignore its own clear.
    func schedule(pasteboard: NSPasteboard, changeCount: Int, seconds: Int,
                  onCleared: @escaping @MainActor (Int) -> Void) {
        cancel()
        guard seconds > 0 else { return }
        task = Task { @MainActor [weak pasteboard] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let pasteboard, pasteboard.changeCount == changeCount else { return }
            pasteboard.clearContents()
            onCleared(pasteboard.changeCount)
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}
