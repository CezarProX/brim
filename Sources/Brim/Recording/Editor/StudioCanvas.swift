// StudioCanvas.swift
// Brim
//
// The preview. Paused: a still rendered by `StudioFrameRenderer` (instant feedback on every
// slider). Playing: the AVPlayer layer showing the custom compositor's output. With the crop or
// hide tool active, the raw recording is shown with an editable rectangle instead.

import AVFoundation
import SwiftUI

struct StudioCanvas: View {
    @ObservedObject var model: StudioModel

    var body: some View {
        GeometryReader { geometry in
            let area = CGRect(origin: .zero, size: geometry.size).insetBy(dx: 28, dy: 18)
            ZStack {
                if let tool = model.tool {
                    StudioRegionEditor(model: model, tool: tool, area: area)
                } else {
                    let canvas = model.previewCanvas
                    let frame = ExportGeometry.aspectFit(canvas, in: area)
                    ZStack {
                        StudioPlayerView(player: model.player)
                            .opacity(model.isPlaying ? 1 : 0)
                        if !model.isPlaying, let preview = model.preview {
                            Image(decorative: preview, scale: 1).resizable().interpolation(.high)
                        }
                    }
                    .frame(width: frame.width, height: frame.height)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
                    .position(x: frame.midX, y: frame.midY)
                    .onTapGesture { model.togglePlay() }
                }
                exportProgress
            }
        }
        .onAppear { model.refreshStill() }
        .onChange(of: model.exportSettings.aspect) { _, _ in model.refreshStill() }
    }

    @ViewBuilder private var exportProgress: some View {
        VStack {
            Spacer()
            StudioExportStatus(model: model).padding(.bottom, 14)
        }
    }
}

/// AVPlayerLayer in SwiftUI.
struct StudioPlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspect
        view.layer = layer
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView.layer as? AVPlayerLayer)?.player = player
    }
}

/// Crop and hidden-area editing over the raw (unstyled) frame.
struct StudioRegionEditor: View {
    @ObservedObject var model: StudioModel
    let tool: StudioModel.Tool
    let area: CGRect
    @State private var draft: CGRect?
    @State private var dragStart: (point: CGPoint, rect: CGRect, mode: DragMode)?

    private enum DragMode { case draw, move, corner(Int) }

    var body: some View {
        let frame = ExportGeometry.aspectFit(model.metadata.pixelSize, in: area.insetBy(dx: 0, dy: 24))
        ZStack(alignment: .topLeading) {
            Group {
                if let raw = model.rawFrame { Image(decorative: raw, scale: 1).resizable() } else { Color.black }
            }
            .frame(width: frame.width, height: frame.height)
            .position(x: frame.midX, y: frame.midY)
            if tool == .hide {
                ForEach(model.edit.hiddenAreas.filter { $0.isActive(at: model.sourceTime) }) { hidden in
                    let rect = denormalise(hidden.rect, in: frame)
                    RoundedRectangle(cornerRadius: 3).fill(StudioTheme.hidden.opacity(0.18))
                        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(StudioTheme.hidden,
                                                                               lineWidth: model.selection == .hidden(hidden.id) ? 2 : 1))
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                        .onTapGesture { model.selection = .hidden(hidden.id) }
                }
            }
            if let rect = activeRect(in: frame) { selectionChrome(rect, frame: frame) }
            hint.position(x: frame.midX, y: frame.minY - 14)
        }
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 1).onChanged { drag($0, frame: frame) }.onEnded { _ in endDrag(frame: frame) })
    }

    private var hint: some View {
        HStack(spacing: 10) {
            Text(tool == .crop ? "Drag the corners to crop" : "Drag to cover an area from the playhead")
                .font(.system(size: 11, weight: .medium)).foregroundStyle(StudioTheme.secondary)
            if tool == .crop {
                Button("Reset") { model.resetCrop() }.controlSize(.small)
            }
            Button("Done") { model.tool = nil }.controlSize(.small).keyboardShortcut(.return, modifiers: [])
        }
    }

    private func activeRect(in frame: CGRect) -> CGRect? {
        if let draft { return draft }
        switch tool {
        case .crop: return denormalise(model.edit.crop, in: frame)
        case .hide: return model.selectedHiddenArea.map { denormalise($0.rect, in: frame) }
        }
    }

    private func selectionChrome(_ rect: CGRect, frame: CGRect) -> some View {
        ZStack(alignment: .topLeading) {
            if tool == .crop {
                Path { path in
                    path.addRect(frame)
                    path.addRect(rect)
                }
                .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))
            }
            Rectangle().strokeBorder(tool == .crop ? Color.white : StudioTheme.hidden, lineWidth: 1.5)
                .frame(width: rect.width, height: rect.height).position(x: rect.midX, y: rect.midY)
            ForEach(0..<4, id: \.self) { corner in
                Circle().fill(.white).frame(width: 11, height: 11)
                    .shadow(color: .black.opacity(0.4), radius: 2)
                    .position(Self.corner(corner, of: rect))
            }
        }
        .allowsHitTesting(false)
    }

    private static func corner(_ index: Int, of rect: CGRect) -> CGPoint {
        CGPoint(x: index % 2 == 0 ? rect.minX : rect.maxX, y: index < 2 ? rect.minY : rect.maxY)
    }

    private func denormalise(_ r: CGRect, in frame: CGRect) -> CGRect {
        CGRect(x: frame.minX + r.minX * frame.width, y: frame.minY + r.minY * frame.height,
               width: r.width * frame.width, height: r.height * frame.height)
    }

    private func normalise(_ r: CGRect, in frame: CGRect) -> CGRect {
        CGRect(x: (r.minX - frame.minX) / frame.width, y: (r.minY - frame.minY) / frame.height,
               width: r.width / frame.width, height: r.height / frame.height)
    }

    private func drag(_ value: DragGesture.Value, frame: CGRect) {
        if dragStart == nil {
            let current = activeRect(in: frame)
            let mode: DragMode
            if let current, let corner = (0..<4).first(where: { hypot(Self.corner($0, of: current).x - value.startLocation.x,
                                                                         Self.corner($0, of: current).y - value.startLocation.y) < 14 }) {
                mode = .corner(corner)
            } else if let current, current.contains(value.startLocation) {
                mode = .move
            } else {
                mode = .draw
            }
            dragStart = (value.startLocation, current ?? .zero, mode)
        }
        guard let start = dragStart else { return }
        let p = CGPoint(x: min(max(value.location.x, frame.minX), frame.maxX), y: min(max(value.location.y, frame.minY), frame.maxY))
        switch start.mode {
        case .draw:
            draft = CGRect(x: min(start.point.x, p.x), y: min(start.point.y, p.y), width: abs(p.x - start.point.x), height: abs(p.y - start.point.y))
        case .move:
            var r = start.rect.offsetBy(dx: value.translation.width, dy: value.translation.height)
            r.origin.x = min(max(r.minX, frame.minX), frame.maxX - r.width)
            r.origin.y = min(max(r.minY, frame.minY), frame.maxY - r.height)
            draft = r
        case .corner(let index):
            let anchor = Self.corner(3 - index, of: start.rect)
            draft = CGRect(x: min(anchor.x, p.x), y: min(anchor.y, p.y), width: abs(p.x - anchor.x), height: abs(p.y - anchor.y))
        }
    }

    private func endDrag(frame: CGRect) {
        defer { draft = nil; dragStart = nil }
        guard let draft, draft.width > 6, draft.height > 6, let start = dragStart else { return }
        let rect = normalise(draft, in: frame)
        switch tool {
        case .crop: model.setCrop(rect)
        case .hide:
            if case .draw = start.mode { model.addHiddenArea(rect) }
            else if let selected = model.selectedHiddenArea { model.updateHiddenArea(selected.id) { $0.rect = rect } }
        }
    }
}
