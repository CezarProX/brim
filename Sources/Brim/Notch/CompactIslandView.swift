import SwiftUI

/// Content sized independently from the expanding shell, matching the compact iPhone hierarchy.
struct RecordingStatusDot: View {
    var body: some View {
        Circle().fill(Color(red: 1, green: 0.27, blue: 0.23)).frame(width: 12, height: 12)
            .accessibilityHidden(true)
    }
}

struct CompactTimerReadout: View {
    let remaining: TimeInterval
    var minimal = false
    var body: some View {
        Text(Self.format(remaining, minimal: minimal))
            .font(.system(size: minimal ? 12 : 16, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(Color.orange)
            .contentTransition(.numericText(countsDown: true))
            .fixedSize()
    }

    static func format(_ remaining: TimeInterval, minimal: Bool = false) -> String {
        let seconds = Int(max(0, min(remaining.isFinite ? remaining : 0, 359_999)).rounded(.up))
        if minimal && seconds >= 3600 { return String(format: "%dh%02d", seconds / 3600, seconds / 60 % 60) }
        if seconds >= 3600 { return String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60) }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

// TimerBubble (the countdown in a detached bubble) lives in IslandBubbleViews.swift.

struct TimerProgressGlyph: View {
    let remaining: TimeInterval
    let duration: TimeInterval
    let paused: Bool
    var body: some View {
        ZStack {
            Circle().stroke(.orange.opacity(0.25), lineWidth: 2)
            Circle().trim(from: 0, to: max(0, min(1, remaining / max(1, duration))))
                .stroke(.orange, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if paused {
                Image(systemName: "pause.fill").font(.system(size: 9, weight: .semibold)).foregroundStyle(.orange)
            } else {
                Path { path in
                    path.move(to: CGPoint(x: 10, y: 5))
                    path.addLine(to: CGPoint(x: 10, y: 10))
                    path.addLine(to: CGPoint(x: 13, y: 12))
                }.stroke(.orange, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(width: 20, height: 20)
        .accessibilityHidden(true)
    }
}
