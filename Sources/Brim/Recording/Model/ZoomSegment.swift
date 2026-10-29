// ZoomSegment.swift
// Brim
//
// Zoom segments ("2.0×" blocks in the editor's lower track) and the generator that turns the
// clicks you made into Screen Studio-style camera moves. Times are source-recording seconds so
// segments stay attached to their content when clips are trimmed, split or sped up.

import CoreGraphics
import Foundation

enum ZoomFocus: Codable, Equatable, Sendable {
    /// The camera follows the (smoothed) pointer, keeping it inside a calm dead zone.
    case cursor
    /// The camera holds one normalised point.
    case fixed(x: Double, y: Double)
}

struct ZoomSegment: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var start: Double
    var end: Double
    var scale: Double
    var focus: ZoomFocus = .cursor
    /// Cuts straight into the zoom and back out instead of easing.
    var instant = false
    /// Created by auto-zoom (regenerating replaces only these).
    var isAuto = false

    static let scaleRange: ClosedRange<Double> = 1.1...4
    static let minimumDuration: Double = 0.4

    var duration: Double { end - start }

    func contains(_ t: Double) -> Bool { t >= start && t < end }
}

struct AutoZoomOptions: Equatable, Sendable {
    /// The zoom starts this long before the first click so it has settled by the click.
    var leadIn: Double = 0.8
    /// The zoom holds this long after the last click of a burst.
    var hold: Double = 1.6
    /// Bursts whose zooms would be closer than this merge into one segment.
    var mergeGap: Double = 1.0
    var minimumDuration: Double = 1.6
    var scale: Double = 1.8
}

enum AutoZoomGenerator {
    /// One segment per burst of left/right presses, clipped to the recording.
    static func segments(clicks: [CursorClick], duration: Double, options: AutoZoomOptions = AutoZoomOptions()) -> [ZoomSegment] {
        let presses = clicks.filter { $0.t >= 0 && $0.t <= duration && $0.x >= -0.02 && $0.x <= 1.02 && $0.y >= -0.02 && $0.y <= 1.02 }
            .sorted { $0.t < $1.t }
        var bursts: [[CursorClick]] = []
        for click in presses {
            if let lastClick = bursts.last?.last,
               click.t - options.leadIn <= lastClick.t + options.hold + options.mergeGap {
                bursts[bursts.count - 1].append(click)
            } else {
                bursts.append([click])
            }
        }
        var result: [ZoomSegment] = []
        for burst in bursts {
            guard let first = burst.first, let last = burst.last else { continue }
            var start = max(0, first.t - options.leadIn)
            var end = min(duration, last.t + options.hold)
            if end - start < options.minimumDuration {
                end = min(duration, start + options.minimumDuration)
                start = max(0, end - options.minimumDuration)
            }
            guard end - start >= ZoomSegment.minimumDuration else { continue }
            if let previous = result.last, start < previous.end { start = previous.end }
            guard end - start >= ZoomSegment.minimumDuration else { continue }
            result.append(ZoomSegment(start: start, end: end, scale: options.scale, focus: .cursor, isAuto: true))
        }
        return result
    }

    /// Replaces the automatic segments, keeping hand-made ones and dropping automatic ones that
    /// would overlap them.
    static func merged(manual existing: [ZoomSegment], generated: [ZoomSegment]) -> [ZoomSegment] {
        let manual = existing.filter { !$0.isAuto }
        let kept = generated.filter { auto in !manual.contains { $0.start < auto.end && auto.start < $0.end } }
        return (manual + kept).sorted { $0.start < $1.start }
    }
}
