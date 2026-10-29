// EditorSidebarView.swift
// Brim
//
// The collapsible left sidebar: presets (save the current look, reset,
// apply a saved one in one click, pick the look for new screenshots) and
// the "Enable styled background" switch with its controls.

import SwiftUI

struct EditorSidebarView: View {
    @ObservedObject var model: ScreenshotEditorModel
    @ObservedObject var presets: StylePresetStore

    init(model: ScreenshotEditorModel) {
        self.model = model
        self.presets = model.presets
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: EditorTheme.sectionSpacing) {
                EditorPresetsSection(model: model, presets: presets)
                Rectangle().fill(EditorTheme.separator).frame(height: 1)
                styledBackgroundToggle
                if model.style.isEnabled {
                    EditorBackgroundControls(model: model)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .animation(.easeInOut(duration: 0.2), value: model.style.isEnabled)
        }
        .frame(width: EditorTheme.sidebarWidth)
        .background(EditorTheme.sidebarBackground)
    }

    private var styledBackgroundToggle: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(L10n.tr("Enable styled background"))
                    .font(EditorTheme.rowTitle)
                    .foregroundStyle(EditorTheme.primaryText)
                Spacer()
                Toggle("", isOn: Binding(get: { model.style.isEnabled }, set: { model.toggleStyledBackground($0) }))
                    .labelsHidden().toggleStyle(.switch).controlSize(.small)
            }
            EditorCaption(text: L10n.tr("Adds gradients, wallpaper, padding and rounded corners."))
        }
    }
}

struct EditorPresetsSection: View {
    @ObservedObject var model: ScreenshotEditorModel
    @ObservedObject var presets: StylePresetStore
    @State private var isNaming = false
    @State private var draftName = ""

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            EditorSectionHeader(title: L10n.tr("Presets"))
            LazyVGrid(columns: columns, spacing: 8) {
                addTile
                resetTile
                ForEach(presets.presets) { preset in presetTile(preset) }
            }
            EditorCaption(text: L10n.tr("Save the look you have now and put it on any screenshot in one click."))
            newCapturePicker
        }
    }

    private var addTile: some View {
        Button { draftName = ""; isNaming = true } label: {
            tileChrome { Image(systemName: "plus").font(.system(size: 15, weight: .semibold)) }
        }
        .buttonStyle(.plain)
        .help(L10n.tr("Save the current look as a preset"))
        .popover(isPresented: $isNaming, arrowEdge: .bottom) { namingPopover }
    }

    private var resetTile: some View {
        Button { model.resetStyle() } label: {
            tileChrome { Image(systemName: "arrow.counterclockwise").font(.system(size: 14, weight: .semibold)) }
        }
        .buttonStyle(.plain)
        .help(L10n.tr("Reset the look"))
    }

    private func tileChrome<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        RoundedRectangle(cornerRadius: EditorTheme.tileCorner, style: .continuous)
            .fill(EditorTheme.controlFill)
            .overlay(RoundedRectangle(cornerRadius: EditorTheme.tileCorner, style: .continuous)
                .strokeBorder(EditorTheme.controlStroke, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            .overlay(content().foregroundStyle(EditorTheme.primaryText))
            .aspectRatio(4.0 / 3.0, contentMode: .fit)
    }

    private func presetTile(_ preset: StylePreset) -> some View {
        let isCurrent = preset.style == model.style
        let isDefault = presets.library.defaultPresetID == preset.id
        return Button { model.apply(preset) } label: {
            VStack(spacing: 4) {
                PresetThumbnail(style: preset.style)
                    .aspectRatio(4.0 / 3.0, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: EditorTheme.tileCorner, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: EditorTheme.tileCorner, style: .continuous)
                        .strokeBorder(isCurrent ? EditorTheme.accent : EditorTheme.controlStroke, lineWidth: isCurrent ? 2 : 1))
                    .overlay(alignment: .topTrailing) {
                        if isDefault {
                            Image(systemName: "star.fill").font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.yellow).padding(4)
                        }
                    }
                Text(verbatim: preset.name).font(.system(size: 10)).lineLimit(1)
                    .foregroundStyle(EditorTheme.secondaryText)
            }
        }
        .buttonStyle(.plain)
        .help(preset.name)
        .contextMenu {
            Button(isDefault ? L10n.tr("Stop using for new screenshots") : L10n.tr("Use for new screenshots")) {
                presets.setDefault(id: isDefault ? nil : preset.id)
            }
            Button(L10n.tr("Update with current look")) { presets.replaceStyle(id: preset.id, with: model.style) }
            Divider()
            Button(L10n.tr("Delete preset"), role: .destructive) { presets.delete(id: preset.id) }
        }
    }

    private var namingPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.tr("Name this look")).font(EditorTheme.rowTitle)
            TextField(L10n.tr("Preset name"), text: $draftName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
                .onSubmit(savePreset)
            HStack {
                Spacer()
                Button(L10n.tr("Cancel")) { isNaming = false }
                Button(L10n.tr("Save preset"), action: savePreset).keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
    }

    private func savePreset() {
        model.saveCurrentStyle(named: draftName)
        isNaming = false
    }

    private var newCapturePicker: some View {
        HStack {
            Text(L10n.tr("New screenshots"))
                .font(EditorTheme.caption).foregroundStyle(EditorTheme.secondaryText)
            Spacer()
            Picker("", selection: Binding(
                get: { presets.library.defaultPresetID },
                set: { presets.setDefault(id: $0) }
            )) {
                Text(L10n.tr("No preset")).tag(UUID?.none)
                ForEach(presets.presets) { preset in Text(verbatim: preset.name).tag(Optional(preset.id)) }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.small)
            .fixedSize()
        }
        .help(L10n.tr("Every screenshot you open in the editor starts with this preset."))
    }
}
