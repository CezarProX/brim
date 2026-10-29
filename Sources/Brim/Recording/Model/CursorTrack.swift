// CursorTrack.swift
// Brim
//
// The pointer log written beside every recording. The raw capture hides the system cursor, so the
// editor redraws it from this track: positions are normalised to the captured rectangle (0...1,
// top-left origin, values outside mean "off the recorded area") and times are recording seconds,
// already aligned to the video's presentation times by `RecordingClock`.

import CoreGraphics
import Foundation

struct CursorSample: Codable, Equatable, Sendable {
    var t: Double
    var x: Double
    var y: Double
}

struct CursorClick: Codable, Equatable, Sendable {
    /// Press time.
    var t: Double
    var x: Double
    var y: Double
    /// 0 = left, 1 = right, 2+ = other.
    var button: Int
    /// Release time, when the release was seen.
    var up: Double?
}

struct CursorTrack: Codable, Equatable, Sendable {
    var samples: [CursorSample]
    var clicks: [CursorClick]

    static let empty = CursorTrack(samples: [], clicks: [])

    var isEmpty: Bool { samples.isEmpty && clicks.isEmpty }

    /// Linear interpolation between samples, holding the first/last position outside them.
    func position(at t: Double) -> CGPoint? {
        guard let first = samples.first, let last = samples.last else { return nil }
        if t <= first.t { return CGPoint(x: first.x, y: first.y) }
        if t >= last.t { return CGPoint(x: last.x, y: last.y) }
        let index = Self.upperBound(samples, t)
        let a = samples[index - 1], b = samples[index]
        let span = b.t - a.t
        let f = span > 0 ? (t - a.t) / span : 1
        return CGPoint(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f)
    }

    /// Clicks pressed inside `range`.
    func clicks(in range: ClosedRange<Double>) -> [CursorClick] {
        clicks.filter { range.contains($0.t) }
    }

    /// Moves every timestamp by `offset` seconds (used when the stream's first frame and the
    /// first pointer event disagree about where zero is).
    func shifted(by offset: Double) -> CursorTrack {
        CursorTrack(
            samples: samples.map { CursorSample(t: $0.t + offset, x: $0.x, y: $0.y) },
            clicks: clicks.map { CursorClick(t: $0.t + offset, x: $0.x, y: $0.y, button: $0.button, up: $0.up.map { $0 + offset }) })
    }

    /// Times at which the pointer did something: moved noticeably, or pressed a button.
    func activityTimes(epsilon: Double = 0.0005) -> [Double] {
        var times: [Double] = []
        var previous: CursorSample?
        for sample in samples {
            if let previous, hypot(sample.x - previous.x, sample.y - previous.y) > epsilon { times.append(sample.t) }
            previous = sample
        }
        times.append(contentsOf: clicks.map(\.t))
        return times.sorted()
    }

    /// Index of the first sample whose time is greater than `t`.
    static func upperBound(_ samples: [CursorSample], _ t: Double) -> Int {
        var low = 0, high = samples.count
        while low < high {
            let mid = (low + high) / 2
            if samples[mid].t <= t { low = mid + 1 } else { high = mid }
        }
        return low
    }
}

/// Maps host-clock timestamps (seconds, the clock ScreenCaptureKit and AVCaptureSession stamp
/// buffers with) to recording time, excluding pauses. The writer retimes video and audio with it
/// and the cursor recorder converts pointer events with it, so all three stay aligned.
struct RecordingClock: Equatable, Sendable {
    struct Pause: Equatable, Sendable {
        var start: Double
        var end: Double?
    }

    /// Host time of the first written video frame; nil until it arrives.
    private(set) var origin: Double?
    private(set) var pauses: [Pause] = []

    var isPaused: Bool { pauses.last.map { $0.end == nil } ?? false }

    mutating func begin(at host: Double) {
        if origin == nil { origin = host }
    }

    mutating func pause(at host: Double) {
        guard !isPaused else { return }
        pauses.append(Pause(start: host, end: nil))
    }

    mutating func resume(at host: Double) {
        guard isPaused, let index = pauses.indices.last else { return }
        pauses[index].end = max(host, pauses[index].start)
    }

    /// Seconds spent paused before `host`.
    func pausedDuration(before host: Double) -> Double {
        pauses.reduce(0) { total, pause in
            guard pause.start < host else { return total }
            return total + (min(pause.end ?? host, host) - pause.start)
        }
    }

    func isInsidePause(_ host: Double) -> Bool {
        pauses.contains { host >= $0.start && host < ($0.end ?? .infinity) }
    }

    /// Recording time for a host timestamp, or nil before the first frame or while paused.
    func recordingTime(host: Double) -> Double? {
        guard let origin, host >= origin, !isInsidePause(host) else { return nil }
        return host - origin - pausedDuration(before: host)
    }

    /// Recording time with times before the origin clamped to zero and pauses folded to their start.
    func clampedRecordingTime(host: Double) -> Double? {
        guard let origin else { return nil }
        if host <= origin { return 0 }
        if let pause = pauses.first(where: { host >= $0.start && host < ($0.end ?? .infinity) }) {
            return max(0, pause.start - origin - pausedDuration(before: pause.start))
        }
        return host - origin - pausedDuration(before: host)
    }
}

/// Pointer events as they arrive, in host time and global top-left points, before alignment.
struct RawPointerEvent: Equatable, Sendable {
    enum Kind: Equatable, Sendable { case move, down(Int), up(Int) }
    var host: Double
    var x: Double
    var y: Double
    var kind: Kind
}

enum CursorTrackBuilder {
    /// Converts raw events to an aligned, normalised track. `captureRect` is the recorded area in
    /// global top-left points. Events during pauses are dropped; the last event before the first
    /// frame becomes the position at time zero.
    static func build(events: [RawPointerEvent], clock: RecordingClock, captureRect: CGRect) -> CursorTrack {
        guard captureRect.width > 0, captureRect.height > 0, clock.origin != nil else { return .empty }
        let sorted = events.sorted { $0.host < $1.host }
        func normalised(_ e: RawPointerEvent) -> (Double, Double) {
            ((e.x - captureRect.minX) / captureRect.width, (e.y - captureRect.minY) / captureRect.height)
        }
        var samples: [CursorSample] = []
        var clicks: [CursorClick] = []
        var openPress: [Int: Int] = [:]
        var lead: RawPointerEvent?
        for event in sorted {
            guard let t = clock.recordingTime(host: event.host) else {
                if let origin = clock.origin, event.host < origin { lead = event }
                continue
            }
            let (x, y) = normalised(event)
            if samples.isEmpty, let lead {
                let (lx, ly) = normalised(lead)
                samples.append(CursorSample(t: 0, x: lx, y: ly))
            }
            samples.append(CursorSample(t: t, x: x, y: y))
            switch event.kind {
            case .move: break
            case .down(let button):
                openPress[button] = clicks.count
                clicks.append(CursorClick(t: t, x: x, y: y, button: button, up: nil))
            case .up(let button):
                if let index = openPress.removeValue(forKey: button) { clicks[index].up = t }
            }
        }
        if samples.isEmpty, let lead {
            let (lx, ly) = normalised(lead)
            samples.append(CursorSample(t: 0, x: lx, y: ly))
        }
        return CursorTrack(samples: samples, clicks: clicks)
    }
}
