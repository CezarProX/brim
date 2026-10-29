// EditorBackgroundControls.swift
// Brim
//
// Controls shown under "Enable styled background": the canvas background
// (gradient grid, solid colours, desktop wallpaper, custom image), padding,
// shadow, corners, aspect ratio and alignment.

import SwiftUI
import UniformTypeIdentifiers

struct EditorBackgroundControls: View {
    @ObservedObject var model: ScreenshotEditorModel

    static let solidColors: [RGBAColor] = [
        RGBAColor(hex: 0xFFFFFF), RGBAColor(hex: 0xF2F2F7), RGBAColor(hex: 0x8E8E93), RGBAColor(hex: 0x1C1C1E),
        RGBAColor(hex: 0x000000), RGBAColor(hex: 0x0A84FF), RGBAColor(hex: 0x30D158), RGBAColor(hex: 0xFFD60A),
        RGBAColor(hex: 0xFF9F0A), RGBAColor(hex: 0xFF375F)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: EditorTheme.sectionSpacing) {
            backgroundSection
            EditorPercentSlider(title: L10n.tr("Padding"), value: binding(\.padding), range: 0...CanvasStyle.maxPadding,
                                displayScale: 100)
            EditorPercentSlider(title: L10n.tr("Shadow"), value: binding(\.shadow), range: 0...1, displayScale: 100)
            cornersSection
            aspectSection
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<CanvasStyle, Value>) -> Binding<Value> {
        Binding(get: { model.style[keyPath: keyPath] }, set: { model.style[keyPath: keyPath] = $0 })
    }

    // MARK: - Background

    private var backgroundSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                EditorSectionHeader(title: L10n.tr("Canvas background"))
                Picker("", selection: kindBinding) {
                    Text(L10n.tr("Gradient")).tag(CanvasBackground.Kind.gradient)
                    Text(L10n.tr("Solid colour")).tag(CanvasBackground.Kind.solid)
                    Text(L10n.tr("Wallpaper")).tag(CanvasBackground.Kind.wallpaper)
                    Text(L10n.tr("Image")).tag(CanvasBackground.Kind.image)
                }
                .labelsHidden().pickerStyle(.menu).controlSize(.small).fixedSize()
            }
            switch model.style.background {
            case .gradient(let id): gradientGrid(selected: id)
            case .solid(let color): solidGrid(selected: color)
            case .desktopWallpaper(let blurred): wallpaperControls(blurred: blurred)
            case .image(let path, let blurred): imageControls(path: path, blurred: blurred)
            }
        }
    }

    private var kindBinding: Binding<CanvasBackground.Kind> {
        Binding(get: { model.style.background.kind }, set: { kind in
            switch kind {
            case .gradient: model.style.background = .gradient(id: GradientLibrary.defaultID)
            case .solid: model.style.background = .solid(Self.solidColors[1])
            case .wallpaper: model.style.background = .desktopWallpaper(blurred: true)
            case .image:
                // Not from inside SwiftUI's binding update: present the panel next turn.
                DispatchQueue.main.async { chooseImage() }
            }
        })
    }

    private let swatchColumns = Array(repeating: GridItem(.flexible(), spacing: 7), count: 5)

    private func gradientGrid(selected: String) -> some View {
        LazyVGrid(columns: swatchColumns, spacing: 7) {
            ForEach(GradientLibrary.presets) { preset in
                swatchButton(isSelected: preset.id == selected, help: L10n.tr(preset.name)) {
                    model.style.background = .gradient(id: preset.id)
                } content: {
                    GradientSwatch(preset: preset)
                }
            }
        }
    }

    private func solidGrid(selected: RGBAColor) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: swatchColumns, spacing: 7) {
                ForEach(Self.solidColors, id: \.self) { color in
                    swatchButton(isSelected: color == selected, help: "") {
                        model.style.background = .solid(color)
                    } content: {
                        Color(cgColor: color.cgColor)
                    }
                }
            }
            ColorPicker(L10n.tr("Custom colour"), selection: Binding(
                get: { Color(cgColor: selected.cgColor) },
                set: { model.style.background = .solid(Self.rgba(from: $0)) }
            ), supportsOpacity: false)
            .font(EditorTheme.caption).foregroundStyle(EditorTheme.secondaryText)
        }
    }

    private func swatchButton<Content: View>(isSelected: Bool, help: String, action: @escaping () -> Void,
                                             @ViewBuilder content: () -> Content) -> some View {
        Button(action: action) {
            content()
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12)))
                .padding(2)
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isSelected ? Color.white : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func wallpaperControls(blurred: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            BackgroundPreview(background: model.style.background)
            Toggle(L10n.tr("Blur wallpaper"), isOn: Binding(
                get: { blurred }, set: { model.style.background = .desktopWallpaper(blurred: $0) }
            ))
            .toggleStyle(.switch).controlSize(.small).font(EditorTheme.caption)
            EditorCaption(text: L10n.tr("Uses your current desktop picture."))
        }
    }

    private func imageControls(path: String, blurred: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            BackgroundPreview(background: model.style.background)
            HStack {
                Button(L10n.tr("Choose Image…")) { chooseImage() }.controlSize(.small)
                Spacer()
                Toggle(L10n.tr("Blur"), isOn: Binding(
                    get: { blurred }, set: { model.style.background = .image(path: path, blurred: $0) }
                ))
                .toggleStyle(.switch).controlSize(.small).font(EditorTheme.caption)
            }
        }
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = L10n.tr("Choose an image for the canvas background")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.style.background = .image(path: url.path, blurred: false)
    }

    static func rgba(from color: Color) -> RGBAColor {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .white
        return RGBAColor(red: Double(ns.redComponent), green: Double(ns.greenComponent), blue: Double(ns.blueComponent))
    }

    // MARK: - Corners, aspect, alignment

    private var cornersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            EditorSectionHeader(title: L10n.tr("Corners"))
            EditorChipRow(options: CornerPreset.allCases, selection: binding(\.corners)) { preset in
                switch preset {
                case .square: return L10n.tr("Square")
                case .small: return L10n.tr("Small")
                case .medium: return L10n.tr("Medium")
                case .large: return L10n.tr("Large")
                }
            }
            Toggle(L10n.tr("Round outer corners"), isOn: binding(\.roundsOuterCorners))
                .toggleStyle(.switch).controlSize(.small).font(EditorTheme.caption)
        }
    }

    private var aspectSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                EditorSectionHeader(title: L10n.tr("Aspect ratio"))
                Picker("", selection: binding(\.aspect)) {
                    ForEach(AspectPreset.allCases, id: \.self) { Text(verbatim: Self.title(for: $0)).tag($0) }
                }
                .labelsHidden().pickerStyle(.menu).controlSize(.small).fixedSize()
            }
            if model.style.aspect != .auto {
                HStack(alignment: .top) {
                    EditorCaption(text: L10n.tr("Alignment"))
                    Spacer()
                    EditorAlignmentGrid(selection: binding(\.alignment))
                }
            }
        }
    }

    static func title(for aspect: AspectPreset) -> String {
        switch aspect {
        case .auto: return L10n.tr("Auto")
        case .wide: return "16:9"
        case .classic: return "4:3"
        case .square: return "1:1"
        case .portrait: return "4:5"
        case .twitter: return L10n.tr("X / Twitter")
        }
    }
}
