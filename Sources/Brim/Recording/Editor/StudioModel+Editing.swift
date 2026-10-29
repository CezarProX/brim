// StudioModel+Editing.swift
// Brim
//
// Toolbar and timeline commands: split, delete, speed, zooms, hidden areas, crop and reset.
// Every command is a single undo step.

import CoreGraphics
import Foundation

extension StudioModel {
    var selectedClip: TimelineClip? {
        guard case .clip(let id) = selection else { return nil }
        return edit.timeline.clips.first { $0.id == id }
    }

    var selectedZoom: ZoomSegment? {
        guard case .zoom(let id) = selection else { return nil }
        return edit.zooms.first { $0.id == id }
    }

    var selectedHiddenArea: HiddenArea? {
        guard case .hidden(let id) = selection else { return nil }
        return edit.hiddenAreas.first { $0.id == id }
    }

    /// Split the clip at the playhead.
    func split() {
        var timeline = edit.timeline
        guard timeline.split(atOutput: playhead) else { return }
        change { $0.timeline = timeline }
        if let index = edit.timeline.clipIndex(atOutput: playhead + 0.001) { selection = .clip(edit.timeline.clips[index].id) }
    }

    /// Delete the selected clip, zoom or hidden area.
    func deleteSelection() {
        switch selection {
        case .clip(let id):
            var timeline = edit.timeline
            guard timeline.delete(clip: id) else { return }
            change { $0.timeline = timeline }
        case .zoom(let id): change { $0.zooms.removeAll { $0.id == id } }
        case .hidden(let id): change { $0.hiddenAreas.removeAll { $0.id == id } }
        case nil: return
        }
        selection = nil
    }

    var canDelete: Bool {
        if case .clip = selection { return edit.timeline.clips.count > 1 }
        return selection != nil
    }

    /// Back to the untouched recording (cuts, zooms, hidden areas and crop), keeping the look.
    func resetEdit() {
        let style = edit.style
        change {
            $0 = StudioEdit.initial(duration: metadata.duration, track: track, style: style)
        }
        selection = nil
        tool = nil
    }

    func setSpeed(_ speed: Double) {
        guard let clip = selectedClip else { return }
        change { $0.timeline.setSpeed(speed, clip: clip.id) }
    }

    func trim(clip id: UUID, start: Bool, toSource value: Double) {
        change("trim-\(id)-\(start)") { start ? $0.timeline.trimStart(clip: id, toSource: value) : $0.timeline.trimEnd(clip: id, toSource: value) }
    }

    // MARK: Zooms

    /// "Add a zoom at the playhead": 2 s at the current zoom level, following the pointer.
    func addZoomAtPlayhead() {
        let start = sourceTime
        let end = min(metadata.duration, start + 2.4)
        guard end - start >= ZoomSegment.minimumDuration,
              !edit.zooms.contains(where: { $0.start < end && start < $0.end }) else { return }
        let zoom = ZoomSegment(start: start, end: end, scale: 2)
        change { $0.zooms = ($0.zooms + [zoom]).sorted { $0.start < $1.start } }
        selection = .zoom(zoom.id)
    }

    /// Replaces automatic zooms with fresh ones from the recorded clicks.
    func regenerateAutoZooms() {
        let generated = AutoZoomGenerator.segments(clicks: track.clicks, duration: metadata.duration)
        change { $0.zooms = AutoZoomGenerator.merged(manual: $0.zooms, generated: generated) }
    }

    func updateZoom(_ id: UUID, coalesce: String? = nil, _ body: (inout ZoomSegment) -> Void) {
        change(coalesce) { edit in
            guard let index = edit.zooms.firstIndex(where: { $0.id == id }) else { return }
            body(&edit.zooms[index])
            edit.zooms[index].isAuto = false
            Self.fit(&edit.zooms, index: index, duration: metadata.duration)
        }
    }

    /// Keeps an edited zoom inside the recording, at least the minimum length and clear of neighbours.
    static func fit(_ zooms: inout [ZoomSegment], index: Int, duration: Double) {
        var zoom = zooms[index]
        let others = zooms.enumerated().filter { $0.offset != index }.map(\.element)
        let floor = others.filter { $0.end <= zoom.start + 0.001 }.map(\.end).max() ?? 0
        let ceiling = others.filter { $0.start >= zoom.end - 0.001 }.map(\.start).min() ?? duration
        zoom.start = max(floor, min(zoom.start, ceiling - ZoomSegment.minimumDuration))
        zoom.end = min(ceiling, max(zoom.end, zoom.start + ZoomSegment.minimumDuration))
        zoom.scale = min(max(zoom.scale, ZoomSegment.scaleRange.lowerBound), ZoomSegment.scaleRange.upperBound)
        zooms[index] = zoom
    }

    // MARK: Hidden areas

    /// Adds a hidden area over `rect` (normalised source) from the playhead for 3 s.
    func addHiddenArea(_ rect: CGRect) {
        let start = sourceTime
        let area = HiddenArea(rect: rect, start: start, end: min(metadata.duration, start + 3))
        guard area.end - area.start >= 0.2 else { return }
        change { $0.hiddenAreas.append(area) }
        selection = .hidden(area.id)
    }

    func updateHiddenArea(_ id: UUID, coalesce: String? = nil, _ body: (inout HiddenArea) -> Void) {
        change(coalesce) { edit in
            guard let index = edit.hiddenAreas.firstIndex(where: { $0.id == id }) else { return }
            body(&edit.hiddenAreas[index])
            var area = edit.hiddenAreas[index]
            area.start = max(0, min(area.start, metadata.duration - 0.2))
            area.end = min(metadata.duration, max(area.end, area.start + 0.2))
            area.rect = StudioEdit.clampedCrop(area.rect)
            edit.hiddenAreas[index] = area
        }
    }

    // MARK: Crop

    func setCrop(_ rect: CGRect) {
        change("crop") { $0.crop = StudioEdit.clampedCrop(rect) }
    }

    func resetCrop() { change { $0.crop = CGRect(x: 0, y: 0, width: 1, height: 1) } }
}
