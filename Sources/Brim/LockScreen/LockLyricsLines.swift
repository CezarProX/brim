import Foundation

/// The three lyric lines the lock screen shows: the one being sung, with a line before and after.
/// Pure so the choice can be tested; the view only draws what this returns.
enum LockLyricsLines {
    enum Role: Equatable { case previous, active, next }
    struct Row: Equatable, Identifiable {
        let id: Int          // index in the lyrics, stable while the window slides
        let text: String
        let role: Role
        let words: [LyricWord]
    }

    /// Before the first line starts the first line is "next"; after the last, the last stays active.
    static func rows(lyrics: TimedLyrics, time: TimeInterval, lookahead: TimeInterval = 0.12) -> [Row] {
        let lines = lyrics.lines
        guard !lines.isEmpty else { return [] }
        guard let current = lyrics.index(at: time, lookahead: lookahead) else {
            return [Row(id: 0, text: lines[0].text, role: .next, words: [])]
        }
        var rows: [Row] = []
        for offset in max(0, current - 1)...min(lines.count - 1, current + 1) {
            let role: Role = offset < current ? .previous : (offset == current ? .active : .next)
            rows.append(Row(id: offset, text: lines[offset].text, role: role,
                            words: role == .active ? lines[offset].words : []))
        }
        return rows
    }

    /// Blank instrumental lines render as a note glyph instead of an empty row.
    static func displayText(_ row: Row) -> String { row.text.isEmpty ? "♪" : row.text }
}

/// Where the lyrics panel sits: directly above the media card, never over the status row.
enum LockLyricsLayout {
    static let width: CGFloat = 520
    static let height: CGFloat = 150
    static let gap: CGFloat = 14

    /// `cardsFrame` and `statusRow` are in screen coordinates (origin bottom-left). nil = no room.
    static func frame(cardsFrame: CGRect?, statusRow: CGRect?, screen: CGRect) -> CGRect? {
        guard let cardsFrame else { return nil }
        let width = min(Self.width, screen.width - LockScreenLayout.margin * 2)
        let y = cardsFrame.maxY + gap
        let ceiling = (statusRow?.minY ?? screen.maxY - screen.height * LockScreenLayout.clockClearance) - gap
        guard ceiling - y >= 90 else { return nil }
        return CGRect(x: screen.midX - width / 2, y: y, width: width, height: min(height, ceiling - y))
    }
}
