// StudioTimeline.swift
// Brim
//
// Time ruler, the clip track (filmstrip thumbnails, speed badges, trim handles), the zoom lane
// ("1.5×" blocks), the hidden-area lane and the playhead. Everything is laid out in output time;
// zooms and hidden areas are stored in source time and mapped through the cut list.

import SwiftUI

struct StudioTimeline: View {
    @ObservedObject var model: StudioModel

    static let inset: CGFloat = 18
    static let rulerHeight: CGFloat = 24
    static let clipTop: CGFloat = 30
    static let clipHeight: CGFloat = 56
    static let zoomTop: CGFloat = 94
    static let laneHeight: CGFloat = 26
    static let hiddenTop: CGFloat = 126

    var body: some View {
        GeometryReader { geometry in
            let contentWidth = max(1, (geometry.size.width - Self.inset * 2) * model.timelineZoom)
            let pps = contentWidth / max(model.duration, 0.1)
            ScrollView(.horizontal) {
                ZStack(alignment: .topLeading) {
                    StudioRuler(duration: model.duration, pps: pps)
                        .frame(width: contentWidth + Self.inset * 2, height: Self.rulerHeight)
                        .contentShape(Rectangle())
                        .gesture(scrub(pps: pps))
                    StudioClipTrack(model: model, pps: pps)
                        .offset(x: Self.inset, y: Self.clipTop)
                    StudioZoomLane(model: model, pps: pps)
                        .offset(x: Self.inset, y: Self.zoomTop)
                    if !model.edit.hiddenAreas.isEmpty {
                        StudioHiddenLane(model: model, pps: pps)
                            .offset(x: Self.inset, y: Self.hiddenTop)
                    }
                    playhead(height: geometry.size.height, pps: pps)
                }
                .frame(width: contentWidth + Self.inset * 2, height: geometry.size.height, alignment: .topLeading)
            }
            .scrollIndicators(model.timelineZoom > 1 ? .visible : .hidden)
        }
        .background(StudioTheme.sidebar.opacity(0.6))
        .overlay(alignment: .top) { Rectangle().fill(StudioTheme.hairline).frame(height: 1) }
    }

    private func scrub(pps: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0).onChanged { value in
            if model.isPlaying { model.pause() }
            model.seek(to: (value.location.x - Self.inset) / pps)
        }
    }

    private func playhead(height: CGFloat, pps: CGFloat) -> some View {
        let x = Self.inset + model.playhead * pps
        return ZStack(alignment: .top) {
            Rectangle().fill(StudioTheme.playhead).frame(width: 2, height: height - 6)
            UnevenRoundedRectangle(topLeadingRadius: 3, bottomLeadingRadius: 7, bottomTrailingRadius: 7, topTrailingRadius: 3)
                .fill(StudioTheme.playhead).frame(width: 13, height: 16)
        }
        .shadow(color: .black.opacity(0.4), radius: 3)
        .frame(width: 13)
        .position(x: x, y: height / 2 - 1)
        .gesture(scrub(pps: pps))
    }
}

/// Ticks every "nice" interval with "00:01.0" labels.
struct StudioRuler: View {
    let duration: Double
    let pps: CGFloat

    static func step(pps: CGFloat) -> Double {
        [0.1, 0.25, 0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300].first { $0 * pps >= 84 } ?? 600
    }

    var body: some View {
        Canvas { context, size in
            let step = Self.step(pps: pps)
            let minor = step / 4
            var t = 0.0
            var index = 0
            while t <= duration + 0.0001 {
                let x = StudioTimeline.inset + t * pps
                let major = index % 4 == 0
                let tick = Path(CGRect(x: x, y: size.height - (major ? 9 : 5), width: 1, height: major ? 9 : 5))
                context.fill(tick, with: .color(.white.opacity(major ? 0.35 : 0.18)))
                if major {
                    context.draw(Text(StudioTheme.timecode(t)).font(.system(size: 10, weight: .medium).monospacedDigit())
                        .foregroundColor(.white.opacity(0.5)), at: CGPoint(x: x + 4, y: 9), anchor: .leading)
                }
                index += 1
                t = Double(index) * minor
            }
        }
    }
}

/// The clips, laid end to end.
struct StudioClipTrack: View {
    @ObservedObject var model: StudioModel
    let pps: CGFloat

    var body: some View {
        let starts = model.edit.timeline.clipStarts
        ZStack(alignment: .topLeading) {
            ForEach(Array(model.edit.timeline.clips.enumerated()), id: \.element.id) { index, clip in
                let width = max(4, clip.outputDuration * pps - 2)
                StudioClipView(model: model, clip: clip, width: width, pps: pps)
                    .offset(x: starts[index] * pps + 1)
            }
        }
    }
}

struct StudioClipView: View {
    @ObservedObject var model: StudioModel
    let clip: TimelineClip
    let width: CGFloat
    let pps: CGFloat
    @State private var trimOrigin: Double?

    private var selected: Bool { model.selection == .clip(clip.id) }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        ZStack(alignment: .topLeading) {
            filmstrip.clipShape(shape)
            shape.strokeBorder(selected ? StudioTheme.playhead : Color.white.opacity(0.14), lineWidth: selected ? 2 : 1)
            if abs(clip.speed - 1) > 0.001 {
                Text(StudioTheme.multiplier(clip.speed))
                    .font(.system(size: 10, weight: .bold)).monospacedDigit()
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(.black.opacity(0.7)))
                    .foregroundStyle(.white)
                    .padding(6)
            }
            if selected {
                handle(start: true).offset(x: -1)
                handle(start: false).offset(x: width - 9)
            }
        }
        .frame(width: width, height: StudioTimeline.clipHeight)
        .contentShape(shape)
        .onTapGesture { location in
            model.selection = .clip(clip.id)
            if let start = model.edit.timeline.clips.firstIndex(of: clip).map({ model.edit.timeline.clipStarts[$0] }) {
                model.seek(to: start + location.x / pps)
            }
        }
    }

    private var filmstrip: some View {
        let aspect = min(max(Double(model.metadata.pixelWidth) / Double(max(1, model.metadata.pixelHeight)), 0.6), 2.4)
        let tile = StudioTimeline.clipHeight * aspect
        let count = max(1, Int((width / tile).rounded(.up)))
        return HStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { index in
                let output = (Double(index) + 0.5) * tile / pps
                let source = clip.sourceStart + min(output, clip.outputDuration) * clip.speed
                if let image = nearestThumbnail(source) {
                    Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: .fill)
                        .frame(width: tile, height: StudioTimeline.clipHeight).clipped()
                } else {
                    Rectangle().fill(StudioTheme.panel).frame(width: tile, height: StudioTimeline.clipHeight)
                }
            }
        }
        .frame(width: width, alignment: .leading)
        .overlay(LinearGradient(colors: [.black.opacity(0.0), .black.opacity(0.25)], startPoint: .top, endPoint: .bottom))
    }

    private func nearestThumbnail(_ time: Double) -> CGImage? {
        model.thumbnails.min { abs($0.time - time) < abs($1.time - time) }?.image
    }

    private func handle(start: Bool) -> some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(StudioTheme.playhead)
            .frame(width: 10, height: StudioTimeline.clipHeight)
            .overlay(Capsule().fill(.black.opacity(0.55)).frame(width: 2, height: 16))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 1).onChanged { value in
                let origin = trimOrigin ?? (start ? clip.sourceStart : clip.sourceEnd)
                trimOrigin = origin
                model.trim(clip: clip.id, start: start, toSource: origin + value.translation.width / pps * clip.speed)
            }.onEnded { _ in trimOrigin = nil })
            .help(start ? "Trim the start" : "Trim the end")
    }
}
