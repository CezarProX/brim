// EditTimeline.swift
// Brim
//
// The cut list: an ordered set of clips, each a range of the source recording played at a speed.
// Everything the editor shows on its time ruler is "output" time (the edited video); everything
// stored against the recording (zooms, hidden areas, cursor) is "source" time. These functions are
// the only bridge between the two.

import Foundation

struct TimelineClip: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var sourceStart: Double
    var sourceEnd: Double
    var speed: Double = 1

    static let speedRange: ClosedRange<Double> = 0.25...4
    static let speedChoices: [Double] = [0.5, 0.75, 1, 1.25, 1.5, 2, 3, 4]

    var sourceDuration: Double { sourceEnd - sourceStart }
    var outputDuration: Double { sourceDuration / speed }
}

struct EditTimeline: Codable, Equatable, Sendable {
    static let minimumClip: Double = 0.1

    var clips: [TimelineClip]
    var sourceDuration: Double

    init(sourceDuration: Double) {
        self.sourceDuration = max(0, sourceDuration)
        clips = [TimelineClip(sourceStart: 0, sourceEnd: self.sourceDuration)]
    }

    var duration: Double { clips.reduce(0) { $0 + $1.outputDuration } }

    /// Output start time of each clip.
    var clipStarts: [Double] {
        var starts: [Double] = []
        var t = 0.0
        for clip in clips { starts.append(t); t += clip.outputDuration }
        return starts
    }

    func outputRange(ofClip index: Int) -> ClosedRange<Double> {
        let start = clipStarts[index]
        return start...(start + clips[index].outputDuration)
    }

    /// The clip playing at output time `t` (the last clip for t at or past the end).
    func clipIndex(atOutput t: Double) -> Int? {
        guard !clips.isEmpty else { return nil }
        var start = 0.0
        for (index, clip) in clips.enumerated() {
            if t < start + clip.outputDuration { return index }
            start += clip.outputDuration
        }
        return clips.count - 1
    }

    func sourceTime(forOutput t: Double) -> Double {
        guard let index = clipIndex(atOutput: max(0, t)) else { return 0 }
        let clip = clips[index]
        let local = min(max(0, t - clipStarts[index]), clip.outputDuration)
        return clip.sourceStart + local * clip.speed
    }

    /// Output time at which source time `s` plays, or nil when it was cut out.
    func outputTime(forSource s: Double) -> Double? {
        var start = 0.0
        for clip in clips {
            if s >= clip.sourceStart && s <= clip.sourceEnd {
                return start + (s - clip.sourceStart) / clip.speed
            }
            start += clip.outputDuration
        }
        return nil
    }

    /// Output intervals where the source range `[from, to]` is visible (a zoom drawn on the ruler).
    func outputRanges(forSource from: Double, _ to: Double) -> [ClosedRange<Double>] {
        var result: [ClosedRange<Double>] = []
        var start = 0.0
        for clip in clips {
            let lo = max(from, clip.sourceStart), hi = min(to, clip.sourceEnd)
            if hi > lo {
                result.append((start + (lo - clip.sourceStart) / clip.speed)...(start + (hi - clip.sourceStart) / clip.speed))
            }
            start += clip.outputDuration
        }
        return result
    }

    // MARK: Editing

    /// Splits the clip under output time `t`. Refuses cuts that would leave a sliver.
    @discardableResult
    mutating func split(atOutput t: Double) -> Bool {
        guard let index = clipIndex(atOutput: t) else { return false }
        let clip = clips[index]
        let cut = sourceTime(forOutput: t)
        guard cut - clip.sourceStart >= Self.minimumClip, clip.sourceEnd - cut >= Self.minimumClip else { return false }
        var left = clip, right = clip
        left.sourceEnd = cut
        right.id = UUID()
        right.sourceStart = cut
        clips.replaceSubrange(index...index, with: [left, right])
        return true
    }

    /// Removes a clip; the last remaining clip can't be deleted.
    @discardableResult
    mutating func delete(clip id: UUID) -> Bool {
        guard clips.count > 1, let index = clips.firstIndex(where: { $0.id == id }) else { return false }
        clips.remove(at: index)
        return true
    }

    mutating func setSpeed(_ speed: Double, clip id: UUID) {
        guard let index = clips.firstIndex(where: { $0.id == id }) else { return }
        clips[index].speed = min(max(speed, TimelineClip.speedRange.lowerBound), TimelineClip.speedRange.upperBound)
    }

    /// Moves a clip's in-point (source seconds), never past its neighbour or its own out-point.
    mutating func trimStart(clip id: UUID, toSource value: Double) {
        guard let index = clips.firstIndex(where: { $0.id == id }) else { return }
        var floor = 0.0
        if index > 0, clips[index - 1].sourceEnd <= clips[index].sourceStart { floor = clips[index - 1].sourceEnd }
        clips[index].sourceStart = min(max(value, floor), clips[index].sourceEnd - Self.minimumClip)
    }

    /// Moves a clip's out-point (source seconds), never past its neighbour or its own in-point.
    mutating func trimEnd(clip id: UUID, toSource value: Double) {
        guard let index = clips.firstIndex(where: { $0.id == id }) else { return }
        var ceiling = sourceDuration
        if index + 1 < clips.count, clips[index + 1].sourceStart >= clips[index].sourceEnd { ceiling = clips[index + 1].sourceStart }
        clips[index].sourceEnd = max(min(value, ceiling), clips[index].sourceStart + Self.minimumClip)
    }
}

/// Bounded undo/redo over whole-document snapshots (documents are small value types).
struct EditHistory<Value: Equatable> {
    private(set) var undoStack: [Value] = []
    private(set) var redoStack: [Value] = []
    let limit: Int

    init(limit: Int = 100) { self.limit = limit }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    /// Call with the state *before* a change.
    mutating func record(_ previous: Value) {
        if undoStack.last == previous { return }
        undoStack.append(previous)
        if undoStack.count > limit { undoStack.removeFirst(undoStack.count - limit) }
        redoStack.removeAll()
    }

    mutating func undo(current: Value) -> Value? {
        guard let previous = undoStack.popLast() else { return nil }
        redoStack.append(current)
        return previous
    }

    mutating func redo(current: Value) -> Value? {
        guard let next = redoStack.popLast() else { return nil }
        undoStack.append(current)
        return next
    }
}
