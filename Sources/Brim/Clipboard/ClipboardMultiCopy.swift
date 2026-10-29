// ClipboardMultiCopy.swift
// Brim
//
// Copies several history entries at once, for "Paste All".

import AppKit

extension ClipboardStore {
    /// Puts the entries on the pasteboard together: text joined one per line, files as one set.
    /// Mixed selections (images among them) can't share one pasteboard write; `copy(_:)` each in turn.
    /// Returns how many entries were written.
    @discardableResult
    func copyTogether(_ chosen: [ClipboardEntry], pasteboard: NSPasteboard? = nil) -> Int {
        let board = pasteboard ?? self.pasteboard
        let live = chosen.filter { candidate in entries.contains { $0.id == candidate.id } }
        guard !live.isEmpty else { return 0 }
        switch ClipboardPastePlan.plan(for: live.map(\.kind)) {
        case .joinedText:
            let text = ClipboardPastePlan.joinedText(live.compactMap(\.text))
            let item = NSPasteboardItem()
            item.setString(text, forType: .string)
            item.setData(Data(), forType: .init("io.github.cezarprox.brim.clipboard-replay"))
            board.clearContents()
            guard board.writeObjects([item]) else { return 0 }
            didWritePasteboard()
            return live.count
        case .allFiles:
            let urls = live.flatMap(\.fileURLs).filter { FileManager.default.fileExists(atPath: $0.path) }
            guard !urls.isEmpty else { return 0 }
            board.clearContents()
            guard board.writeObjects(urls.map { $0 as NSURL }) else { return 0 }
            board.setData(Data(), forType: .init("io.github.cezarprox.brim.clipboard-replay"))
            didWritePasteboard()
            return live.count
        case .sequential:
            return live.last.map { copy($0) ? 1 : 0 } ?? 0
        }
    }
}
