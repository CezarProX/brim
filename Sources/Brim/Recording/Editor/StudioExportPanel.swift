// StudioExportPanel.swift
// Brim
//
// Export options (format, codec, size, shape, frame rate), and the progress / result pill shown
// over the canvas while exporting and afterwards.

import SwiftUI

struct StudioExportPanel: View {
    @ObservedObject var model: StudioModel
    let onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            StudioSectionTitle(title: "Export options")
            Picker("Format", selection: $model.exportSettings.format) {
                ForEach(ExportFormat.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            if model.exportSettings.format == .mp4 {
                row("Codec") {
                    Picker("Codec", selection: $model.exportSettings.codec) {
                        ForEach(ExportCodec.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                }
            }
            row("Resolution") {
                Picker("Resolution", selection: $model.exportSettings.resolution) {
                    ForEach(ExportResolution.allCases, id: \.self) { Text(LocalizedStringKey($0.title)).tag($0) }
                }
            }
            row("Shape") {
                Picker("Shape", selection: $model.exportSettings.aspect) {
                    ForEach(ExportAspect.allCases, id: \.self) { Text(LocalizedStringKey($0.title)).tag($0) }
                }
            }
            row("Frame rate") {
                if model.exportSettings.format == .gif {
                    Picker("Frame rate", selection: $model.exportSettings.gifFPS) {
                        ForEach(ExportSettings.gifFPSChoices, id: \.self) { Text("\($0) fps").tag($0) }
                    }
                } else {
                    Picker("Frame rate", selection: $model.exportSettings.fps) {
                        ForEach(ExportSettings.fpsChoices, id: \.self) { Text("\($0) fps").tag($0) }
                    }
                }
            }
            let canvas = model.renderer.canvasSize(model.exportSettings)
            Text("\(Int(canvas.width)) × \(Int(canvas.height)) · \(StudioTheme.timecode(model.duration))")
                .font(.system(size: 11)).monospacedDigit().foregroundStyle(StudioTheme.tertiary)
            Button {
                onStart()
                model.export()
            } label: {
                Text(model.exportSettings.format == .gif ? "Save GIF" : "Save Video")
                    .font(.system(size: 13, weight: .semibold)).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.isExporting)
            Text("Saved to \(model.exportFolder.lastPathComponent)").font(.system(size: 11)).foregroundStyle(StudioTheme.tertiary)
        }
        .environment(\.colorScheme, .dark)
    }

    private func row<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(StudioTheme.secondary)
            Spacer()
            content().labelsHidden().fixedSize()
        }
    }
}

/// Progress while exporting; Reveal / Copy / Share once done.
struct StudioExportStatus: View {
    @ObservedObject var model: StudioModel

    var body: some View {
        Group {
            switch model.exportState {
            case .idle:
                EmptyView()
            case .running(let format, let progress):
                pill {
                    ProgressView().controlSize(.small)
                    Text(format == .gif ? "Creating GIF…" : "Exporting…").font(.system(size: 12, weight: .medium))
                    ProgressView(value: progress).frame(width: 140).tint(StudioTheme.accent)
                    Text("\(Int(progress * 100))%").font(.system(size: 11, weight: .semibold)).monospacedDigit().frame(width: 34)
                    Button("Cancel") { model.cancelExport() }.controlSize(.small)
                }
            case .finished(let url):
                pill {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text(url.lastPathComponent).font(.system(size: 12, weight: .medium)).lineLimit(1).frame(maxWidth: 220)
                    Button("Show in Finder") { model.revealExport() }.controlSize(.small)
                    Button("Copy") { model.copyExport() }.controlSize(.small)
                    ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }.controlSize(.small)
                    Button { model.dismissExportResult() } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain).foregroundStyle(StudioTheme.secondary)
                }
            case .failed(let message):
                pill {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(message).font(.system(size: 12, weight: .medium)).lineLimit(2).frame(maxWidth: 320)
                    Button { model.dismissExportResult() } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain).foregroundStyle(StudioTheme.secondary)
                }
            }
        }
        .animation(.snappy(duration: 0.25), value: model.exportState)
    }

    private func pill<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 10, content: content)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(Capsule().fill(.black.opacity(0.78)))
            .overlay(Capsule().strokeBorder(StudioTheme.hairline))
            .foregroundStyle(StudioTheme.primary)
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
