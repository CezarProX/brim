// StudioSidebar.swift
// Brim
//
// The look of the recording: presets, canvas background, padding, shadow and corners, with the
// selected clip / zoom / hidden area's options on top when something is selected.

import SwiftUI

struct StudioSidebar: View {
    @ObservedObject var model: StudioModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                StudioInspector(model: model)
                presets
                background
                VStack(alignment: .leading, spacing: 16) {
                    StudioSliderRow(title: "Padding", value: style(\.padding, "padding"), range: RecordingStyle.paddingRange)
                    StudioSliderRow(title: "Shadow", value: style(\.shadow, "shadow"))
                }
                corners
                autoZoom
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
        }
        .scrollIndicators(.hidden)
    }

    private func style<T: Equatable>(_ path: WritableKeyPath<RecordingStyle, T>, _ key: String) -> Binding<T> {
        Binding(get: { model.edit.style[keyPath: path] },
                set: { value in model.change(key) { $0.style[keyPath: path] = value } })
    }

    // MARK: Presets

    private var presets: some View {
        VStack(alignment: .leading, spacing: 10) {
            StudioSectionTitle(title: "Presets")
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(40), spacing: 8), count: 5), alignment: .leading, spacing: 8) {
                presetTile(symbol: "plus", help: "Save the current look as a preset") { model.savePreset() }
                presetTile(symbol: "arrow.counterclockwise", help: "Reset the recording style") { model.resetStyle() }
                ForEach(model.presets) { preset in
                    Button { model.apply(preset) } label: {
                        StudioSwatch(background: preset.style.background, selected: preset.style == model.edit.style)
                    }
                    .buttonStyle(.plain)
                    .help(preset.name)
                    .contextMenu { Button("Delete Preset") { model.deletePreset(preset) } }
                }
            }
            Text("Save the look you have now and put it on any recording in one click.")
                .font(.system(size: 11)).foregroundStyle(StudioTheme.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func presetTile(symbol: String, help: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
                .frame(width: 40, height: 40)
                .foregroundStyle(StudioTheme.secondary)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(StudioTheme.well))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(StudioTheme.hairline))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: Background

    private enum BackgroundKind: String { case gradient, color }

    private var backgroundKind: BackgroundKind {
        if case .solid = model.edit.style.background { return .color }
        return .gradient
    }

    private var background: some View {
        VStack(alignment: .leading, spacing: 10) {
            StudioSectionTitle(title: "Background")
            HStack {
                Text("Canvas background").font(.system(size: 12, weight: .medium)).foregroundStyle(StudioTheme.secondary)
                Spacer()
                Menu {
                    Button("Gradient") { model.change { $0.style.background = .gradient(0) } }
                    Button("Color") { model.change { $0.style.background = .solid(StudioBackground.solidChoices[0]) } }
                } label: {
                    Text(backgroundKind == .gradient ? "Gradient" : "Color").font(.system(size: 12, weight: .medium))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                if backgroundKind == .gradient {
                    ForEach(StudioGradient.all) { gradient in
                        swatchButton(.gradient(gradient.id))
                    }
                } else {
                    ForEach(StudioBackground.solidChoices, id: \.self) { color in
                        swatchButton(.solid(color))
                    }
                }
            }
        }
    }

    private func swatchButton(_ background: StudioBackground) -> some View {
        Button { model.change { $0.style.background = background } } label: {
            StudioSwatch(background: background, selected: model.edit.style.background == background)
        }
        .buttonStyle(.plain)
    }

    // MARK: Corners

    private var corners: some View {
        VStack(alignment: .leading, spacing: 10) {
            StudioSectionTitle(title: "Corners")
            Text("Recording").font(.system(size: 12, weight: .medium)).foregroundStyle(StudioTheme.secondary)
            HStack(spacing: 6) {
                ForEach(StudioCornerStyle.allCases, id: \.self) { corner in
                    let selected = model.edit.style.corners == corner
                    Button { model.change { $0.style.corners = corner } } label: {
                        VStack(spacing: 5) {
                            UnevenRoundedRectangle(topLeadingRadius: CGFloat(corner.factor * 340), style: .continuous)
                                .stroke(selected ? StudioTheme.accent : StudioTheme.secondary, lineWidth: 2)
                                .frame(width: 18, height: 18)
                                .offset(x: 3, y: 3)
                                .clipped()
                            Text(LocalizedStringKey(corner.title)).font(.system(size: 10, weight: .medium))
                        }
                        .frame(maxWidth: .infinity).frame(height: 50)
                        .foregroundStyle(selected ? StudioTheme.primary : StudioTheme.secondary)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(selected ? StudioTheme.accent.opacity(0.16) : StudioTheme.well))
                        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(selected ? StudioTheme.accent.opacity(0.7) : StudioTheme.hairline))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Zoom

    private var autoZoom: some View {
        VStack(alignment: .leading, spacing: 8) {
            StudioSectionTitle(title: "Zoom in on the action")
            Text("Turns the clicks you made into smooth camera moves.")
                .font(.system(size: 11)).foregroundStyle(StudioTheme.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button { model.regenerateAutoZooms() } label: {
                    Label("Auto zoom", systemImage: "sparkles").font(.system(size: 12, weight: .medium))
                }
                .disabled(model.track.clicks.isEmpty)
                Button { model.addZoomAtPlayhead() } label: {
                    Label("Add zoom at playhead", systemImage: "plus.magnifyingglass").font(.system(size: 12, weight: .medium))
                }
            }
            .controlSize(.small)
            if model.track.clicks.isEmpty {
                Text("No clicks were recorded").font(.system(size: 11)).foregroundStyle(StudioTheme.tertiary)
            }
        }
    }
}

/// A rounded background swatch.
struct StudioSwatch: View {
    let background: StudioBackground
    let selected: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(fill)
            .aspectRatio(1, contentMode: .fit)
            .frame(minWidth: 30, maxWidth: 44)
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(.white.opacity(0.12)))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(selected ? StudioTheme.primary : .clear, lineWidth: 2).padding(-3))
            .padding(3)
    }

    private var fill: AnyShapeStyle {
        switch background {
        case .solid(let color):
            return AnyShapeStyle(Color(red: color.r, green: color.g, blue: color.b))
        case .gradient(let id):
            let gradient = StudioGradient.preset(id)
            let radians = gradient.angle * .pi / 180
            let dx = cos(radians) / 2, dy = sin(radians) / 2
            return AnyShapeStyle(LinearGradient(
                colors: gradient.colors.map { Color(red: $0.r, green: $0.g, blue: $0.b) },
                startPoint: UnitPoint(x: 0.5 - dx, y: 0.5 - dy), endPoint: UnitPoint(x: 0.5 + dx, y: 0.5 + dy)))
        }
    }
}
