// StudioTimelineLanes.swift
// Brim
//
// The zoom lane and the hidden-area lane under the clips. Blocks can be selected, dragged in time
// and resized from either edge.

import SwiftUI

struct StudioZoomLane: View {
    @ObservedObject var model: StudioModel
    let pps: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 7, style: .continuous).fill(StudioTheme.well)
                .frame(width: max(1, model.duration * pps), height: StudioTimeline.laneHeight)
            if model.edit.zooms.isEmpty {
                Text("Zooms appear here. Add one at the playhead or let auto zoom follow your clicks.")
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(StudioTheme.tertiary)
                    .padding(.leading, 10).frame(height: StudioTimeline.laneHeight)
            }
            ForEach(model.edit.zooms) { zoom in
                ForEach(Array(model.edit.timeline.outputRanges(forSource: zoom.start, zoom.end).enumerated()), id: \.offset) { _, range in
                    StudioLaneBlock(
                        label: StudioTheme.multiplier(zoom.scale), symbol: zoom.instant ? "bolt.fill" : "plus.magnifyingglass",
                        tint: StudioTheme.zoom, selected: model.selection == .zoom(zoom.id),
                        width: max(14, (range.upperBound - range.lowerBound) * pps), pps: pps,
                        onSelect: { model.selection = .zoom(zoom.id) },
                        onDrag: { edge, delta in
                            model.updateZoom(zoom.id, coalesce: "zoom-drag-\(zoom.id)") { segment in
                                Self.shift(&segment.start, &segment.end, edge: edge, delta: delta)
                            }
                        })
                    .offset(x: range.lowerBound * pps)
                }
            }
        }
    }

    /// Applies a drag (source seconds) to a start/end pair: move both, or one edge.
    static func shift(_ start: inout Double, _ end: inout Double, edge: StudioLaneBlock.Edge, delta: Double) {
        switch edge {
        case .body: start += delta; end += delta
        case .leading: start = min(start + delta, end - ZoomSegment.minimumDuration)
        case .trailing: end = max(end + delta, start + ZoomSegment.minimumDuration)
        }
    }
}

struct StudioHiddenLane: View {
    @ObservedObject var model: StudioModel
    let pps: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 7, style: .continuous).fill(StudioTheme.well)
                .frame(width: max(1, model.duration * pps), height: StudioTimeline.laneHeight)
            ForEach(model.edit.hiddenAreas) { area in
                ForEach(Array(model.edit.timeline.outputRanges(forSource: area.start, area.end).enumerated()), id: \.offset) { _, range in
                    StudioLaneBlock(
                        label: area.kind == .blur ? L10n.tr("Blur") : L10n.tr("Pixelate"), symbol: "eye.slash",
                        tint: StudioTheme.hidden, selected: model.selection == .hidden(area.id),
                        width: max(14, (range.upperBound - range.lowerBound) * pps), pps: pps,
                        onSelect: { model.selection = .hidden(area.id) },
                        onDrag: { edge, delta in
                            model.updateHiddenArea(area.id, coalesce: "hidden-drag-\(area.id)") { hidden in
                                StudioZoomLane.shift(&hidden.start, &hidden.end, edge: edge, delta: delta)
                            }
                        })
                    .offset(x: range.lowerBound * pps)
                }
            }
        }
    }
}

/// A coloured block in a lane. Reports drags as source-second deltas since the last change.
struct StudioLaneBlock: View {
    enum Edge { case leading, trailing, body }

    let label: String
    let symbol: String
    let tint: Color
    let selected: Bool
    let width: CGFloat
    let pps: CGFloat
    let onSelect: () -> Void
    let onDrag: (Edge, Double) -> Void
    @State private var applied: CGFloat = 0

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 9, weight: .bold))
            Text(label).font(.system(size: 10, weight: .bold)).monospacedDigit().lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .frame(width: width, height: StudioTimeline.laneHeight, alignment: .leading)
        .background(shape.fill(tint.opacity(selected ? 0.95 : 0.7)))
        .overlay(shape.strokeBorder(selected ? Color.white : tint.opacity(0.9), lineWidth: selected ? 1.5 : 1))
        .clipShape(shape)
        .contentShape(shape)
        .onTapGesture(perform: onSelect)
        .gesture(drag(.body))
        .overlay(alignment: .leading) { edgeHandle(.leading) }
        .overlay(alignment: .trailing) { edgeHandle(.trailing) }
    }

    private func edgeHandle(_ edge: Edge) -> some View {
        Rectangle().fill(Color.white.opacity(selected ? 0.9 : 0.001))
            .frame(width: selected ? 4 : 8, height: StudioTimeline.laneHeight - 8)
            .clipShape(Capsule())
            .padding(.horizontal, 2)
            .contentShape(Rectangle().inset(by: -4))
            .gesture(drag(edge))
            .onHover { inside in if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() } }
    }

    private func drag(_ edge: Edge) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                onSelect()
                let step = value.translation.width - applied
                applied = value.translation.width
                onDrag(edge, step / pps)
            }
            .onEnded { _ in applied = 0 }
    }
}
