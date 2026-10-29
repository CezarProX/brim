// StudioTransport.swift
// Brim
//
// "00:03.0 / 00:06.0" · previous / play / next · timeline zoom − 1.0× + fit.

import SwiftUI

struct StudioTransport: View {
    @ObservedObject var model: StudioModel

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                HStack(spacing: 4) {
                    Text(StudioTheme.timecode(model.playhead)).foregroundStyle(StudioTheme.primary)
                    Text("/").foregroundStyle(StudioTheme.tertiary)
                    Text(StudioTheme.timecode(model.duration)).foregroundStyle(StudioTheme.secondary)
                }
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                Spacer()
                HStack(spacing: 2) {
                    StudioIconButton(symbol: "minus", help: "Zoom out of the timeline", size: 26,
                                     isEnabled: model.timelineZoom > 1) { setZoom(model.timelineZoom / 1.5) }
                    Text(StudioTheme.multiplier(model.timelineZoom))
                        .font(.system(size: 11, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(StudioTheme.secondary).frame(width: 40)
                    StudioIconButton(symbol: "plus", help: "Zoom into the timeline", size: 26,
                                     isEnabled: model.timelineZoom < 12) { setZoom(model.timelineZoom * 1.5) }
                    StudioIconButton(symbol: "arrow.left.and.right", help: "Fit the timeline", size: 26) { setZoom(1) }
                }
            }
            HStack(spacing: 8) {
                StudioIconButton(symbol: "backward.end.fill", help: "Previous cut", size: 30) { model.step(forward: false) }
                Button { model.togglePlay() } label: {
                    Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 15, weight: .bold))
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(Color.white.opacity(0.1)))
                        .foregroundStyle(StudioTheme.primary)
                }
                .buttonStyle(.plain)
                .help(model.isPlaying ? "Pause" : "Play")
                StudioIconButton(symbol: "forward.end.fill", help: "Next cut", size: 30) { model.step(forward: true) }
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 52)
        .overlay(alignment: .top) { Rectangle().fill(StudioTheme.hairline).frame(height: 1) }
    }

    private func setZoom(_ value: Double) {
        withAnimation(.snappy(duration: 0.2)) { model.timelineZoom = min(max(value, 1), 12) }
    }
}
