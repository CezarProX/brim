// ClipboardSelection.swift
// Brim
//
// Pure state for the library's multi-select and keyboard cursor. Selection order is click order,
// which is the order "Paste All" pastes in.

import Foundation

struct ClipboardSelection: Equatable {
    /// Selected item ids in the order they were chosen.
    private(set) var ordered: [String] = []
    /// The keyboard cursor.
    var cursor: String?

    var isEmpty: Bool { ordered.isEmpty }
    var count: Int { ordered.count }
    func contains(_ id: String) -> Bool { ordered.contains(id) }

    mutating func toggle(_ id: String) {
        if let index = ordered.firstIndex(of: id) { ordered.remove(at: index) } else { ordered.append(id) }
        cursor = id
    }

    mutating func selectAll(_ ids: [String]) {
        ordered = ids
    }

    mutating func clear() { ordered = [] }

    /// Drops ids that are no longer in the library (deleted, filtered out).
    mutating func prune(keeping visible: [String]) {
        let live = Set(visible)
        ordered = ordered.filter(live.contains)
        if let cursor, !live.contains(cursor) { self.cursor = nil }
    }

    /// Moves the cursor by `delta` through `ids`, clamping at the ends; starts at the first item.
    mutating func move(_ delta: Int, in ids: [String]) {
        guard !ids.isEmpty else { cursor = nil; return }
        guard let current = cursor, let index = ids.firstIndex(of: current) else {
            cursor = delta < 0 ? ids.last : ids.first
            return
        }
        cursor = ids[min(ids.count - 1, max(0, index + delta))]
    }

    /// What a command acts on: the selection if there is one, otherwise the cursor item.
    func targets(in ids: [String]) -> [String] {
        if !ordered.isEmpty { return ordered.filter(ids.contains) }
        if let cursor, ids.contains(cursor) { return [cursor] }
        return []
    }
}

/// How several entries reach the pasteboard in one go.
enum ClipboardPastePlan: Equatable {
    case joinedText
    case allFiles
    case sequential

    static func plan(for kinds: [ClipboardEntry.Kind]) -> ClipboardPastePlan {
        if kinds.allSatisfy({ [.text, .link, .color].contains($0) }) { return .joinedText }
        if kinds.allSatisfy({ $0 == .file }) { return .allFiles }
        return .sequential
    }

    /// Text items joined one per line, in the order given.
    static func joinedText(_ texts: [String]) -> String {
        texts.map { $0.trimmingCharacters(in: .newlines) }.joined(separator: "\n")
    }
}
