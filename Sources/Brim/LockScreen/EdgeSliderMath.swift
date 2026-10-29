import Foundation

enum EdgeSliderKind: String, Equatable { case volume, brightness }

/// Maps between a 0...1 level and a vertical pill. Pure geometry for the edge sliders.
enum EdgeSliderMath {
    /// The level for a point `y` measured from the TOP of a track of `height` (SwiftUI space).
    static func level(forY y: CGFloat, height: CGFloat) -> Double {
        guard height > 0, y.isFinite else { return 0 }
        return HUDLevelMath.clamp(1 - Double(y / height))
    }

    /// Height of the filled part for a level.
    static func fillHeight(level: Double, trackHeight: CGFloat) -> CGFloat {
        trackHeight * CGFloat(HUDLevelMath.clamp(level))
    }

    /// Snaps a dragged level to the 16-step grid like the keyboard does; fine = quarter steps.
    static func snapped(_ level: Double, fine: Bool) -> Double {
        let size = HUDLevelMath.stepSize(fine: fine)
        return HUDLevelMath.clamp((HUDLevelMath.clamp(level) / size).rounded() * size)
    }
}

/// First key press after a quiet spell shows the wide pill; presses while it is still up shrink it
/// to the thin one so it does not shout on every step.
struct EdgeSliderSession: Equatable {
    enum Style: Equatable { case wide, thin }
    static let visibleDuration: TimeInterval = 1.8
    static let wideDuration: TimeInterval = 0.9

    private(set) var lastPress: Date?
    private(set) var widePressAt: Date?

    mutating func press(now: Date) -> Style {
        defer { lastPress = now }
        guard let last = lastPress, now.timeIntervalSince(last) < Self.visibleDuration else {
            widePressAt = now
            return .wide
        }
        // Held keys keep the wide pill only for a moment, then it slims down.
        if let wide = widePressAt, now.timeIntervalSince(wide) < Self.wideDuration { return .wide }
        return .thin
    }

    func isVisible(now: Date) -> Bool {
        lastPress.map { now.timeIntervalSince($0) < Self.visibleDuration } ?? false
    }
}
