// EditorToolStripView.swift
// Brim
//
// The row of round icon buttons above the canvas: text and style, undo /
// redo, zoom, crop and selection, the drawing tools, the redaction and
// focus tools, and the current colour. Every button carries its keyboard
// shortcut in its tooltip.

import SwiftUI

struct EditorToolItem: Identifiable {
    let tool: AnnotationTool?
    let symbol: String
    let title: String
    let shortcut: Character

    var id: String { tool?.rawValue ?? "select" }

    @MainActor static let drawing: [EditorToolItem] = [
        EditorToolItem(tool: .arrow, symbol: "arrow.up.right", title: L10n.tr("Arrow"), shortcut: "a"),
        EditorToolItem(tool: .curvedArrow, symbol: "arrow.uturn.right", title: L10n.tr("Curved arrow"), shortcut: "u"),
        EditorToolItem(tool: .line, symbol: "line.diagonal", title: L10n.tr("Line"), shortcut: "l"),
        EditorToolItem(tool: .rectangle, symbol: "rectangle", title: L10n.tr("Rectangle"), shortcut: "r"),
        EditorToolItem(tool: .ellipse, symbol: "circle", title: L10n.tr("Ellipse"), shortcut: "o"),
        EditorToolItem(tool: .pen, symbol: "scribble", title: L10n.tr("Pen"), shortcut: "p"),
        EditorToolItem(tool: .highlighter, symbol: "highlighter", title: L10n.tr("Highlighter"), shortcut: "h")
    ]

    @MainActor static let focus: [EditorToolItem] = [
        EditorToolItem(tool: .blur, symbol: "eye.slash", title: L10n.tr("Blur"), shortcut: "b"),
        EditorToolItem(tool: .pixelate, symbol: "square.grid.3x3.fill", title: L10n.tr("Pixelate"), shortcut: "x"),
        EditorToolItem(tool: .spotlight, symbol: "flashlight.on.fill", title: L10n.tr("Spotlight"), shortcut: "s"),
        EditorToolItem(tool: .magnifier, symbol: "magnifyingglass.circle", title: L10n.tr("Magnifier"), shortcut: "m"),
        EditorToolItem(tool: .counter, symbol: "1.circle", title: L10n.tr("Step counter"), shortcut: "n")
    ]

    @MainActor static let navigation: [EditorToolItem] = [
        EditorToolItem(tool: .crop, symbol: "crop", title: L10n.tr("Crop"), shortcut: "c"),
        EditorToolItem(tool: nil, symbol: "cursorarrow", title: L10n.tr("Select"), shortcut: "v")
    ]

    @MainActor static let text = EditorToolItem(tool: .text, symbol: "textformat", title: L10n.tr("Text"), shortcut: "t")

    @MainActor static var all: [EditorToolItem] { [text] + navigation + drawing + focus }

    /// The tool a bare (unmodified) key selects.
    @MainActor static func item(forShortcut key: Character) -> EditorToolItem? {
        all.first { $0.shortcut == key }
    }
}

struct EditorToolStripView: View {
    @ObservedObject var model: ScreenshotEditorModel
    @State private var showsStylePopover = false

    var body: some View {
        let _ = model.revision
        HStack(spacing: 4) {
            toolButton(.text)
            styleButton(symbol: "paintpalette", help: L10n.tr("Colour and stroke"))
            divider
            iconButton("arrow.uturn.backward", help: L10n.tr("Undo (⌘Z)"), enabled: model.session.canUndo) { model.undo() }
            iconButton("arrow.uturn.forward", help: L10n.tr("Redo (⇧⌘Z)"), enabled: model.session.canRedo) { model.redo() }
            divider
            zoomControls
            divider
            ForEach(EditorToolItem.navigation) { toolButton($0) }
            divider
            ForEach(EditorToolItem.drawing) { toolButton($0) }
            divider
            ForEach(EditorToolItem.focus) { toolButton($0) }
            divider
            colorCircle
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.white.opacity(0.05)))
        .overlay(Capsule().strokeBorder(EditorTheme.controlStroke))
    }

    private var divider: some View {
        Rectangle().fill(EditorTheme.separator).frame(width: 1, height: 18).padding(.horizontal, 3)
    }

    private var zoomControls: some View {
        HStack(spacing: 2) {
            iconButton("minus", help: L10n.tr("Zoom out (⌘−)")) { model.zoomOut() }
            Button { model.zoomToActualSize() } label: {
                Text(verbatim: "\(Int((model.zoom * 100).rounded()))%")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(EditorTheme.primaryText)
                    .frame(minWidth: 40, minHeight: EditorTheme.toolButtonSize)
            }
            .buttonStyle(EditorRoundButtonStyle(isSelected: false, isCapsule: true))
            .help(L10n.tr("Actual size (⌘0)"))
            iconButton("plus", help: L10n.tr("Zoom in (⌘+)")) { model.zoomIn() }
            iconButton("arrow.down.right.and.arrow.up.left", help: L10n.tr("Zoom to fit (⌘9)"),
                       selected: model.isZoomToFit) { model.zoomToFit() }
        }
    }

    private func toolButton(_ item: EditorToolItem) -> some View {
        let selected = model.currentTool == item.tool
        let symbol = filledSymbol(for: item)
        return Button { model.select(tool: item.tool) } label: {
            Image(systemName: symbol).font(.system(size: 13, weight: .medium))
                .frame(width: EditorTheme.toolButtonSize, height: EditorTheme.toolButtonSize)
        }
        .buttonStyle(EditorRoundButtonStyle(isSelected: selected))
        .help("\(item.title) (\(item.shortcut.uppercased()))")
        .accessibilityLabel(item.title)
        .contextMenu { fillMenu(for: item) }
    }

    /// Rectangle and ellipse show a filled glyph while shapes are filled.
    private func filledSymbol(for item: EditorToolItem) -> String {
        guard model.annotationStyle.isFilled, item.tool == .rectangle || item.tool == .ellipse else { return item.symbol }
        return item.symbol + ".fill"
    }

    @ViewBuilder
    private func fillMenu(for item: EditorToolItem) -> some View {
        if item.tool == .rectangle || item.tool == .ellipse {
            Button(L10n.tr("Outline")) { setFilled(false, tool: item.tool) }
            Button(L10n.tr("Filled")) { setFilled(true, tool: item.tool) }
        }
    }

    private func setFilled(_ filled: Bool, tool: AnnotationTool?) {
        var style = model.annotationStyle
        style.isFilled = filled
        model.annotationStyle = style
        if model.currentTool != tool { model.select(tool: tool) }
    }

    private func iconButton(_ symbol: String, help: String, enabled: Bool = true, selected: Bool = false,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
                .frame(width: EditorTheme.toolButtonSize, height: EditorTheme.toolButtonSize)
        }
        .buttonStyle(EditorRoundButtonStyle(isSelected: selected))
        .disabled(!enabled)
        .help(help)
    }

    private func styleButton(symbol: String, help: String) -> some View {
        iconButton(symbol, help: help, selected: showsStylePopover) { showsStylePopover.toggle() }
            .popover(isPresented: $showsStylePopover, arrowEdge: .bottom) {
                EditorStylePopover(model: model)
            }
    }

    private var colorCircle: some View {
        Button { showsStylePopover.toggle() } label: {
            Circle().fill(Color(nsColor: model.annotationStyle.color))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.85), lineWidth: 2))
                .frame(width: 20, height: 20)
                .frame(width: EditorTheme.toolButtonSize, height: EditorTheme.toolButtonSize)
        }
        .buttonStyle(EditorRoundButtonStyle(isSelected: false))
        .help(L10n.tr("Colour"))
    }
}

/// A round (or capsule) button that tints when selected and lifts on hover.
struct EditorRoundButtonStyle: ButtonStyle {
    var isSelected: Bool
    var isCapsule = false

    func makeBody(configuration: Configuration) -> some View {
        EditorRoundButtonBody(configuration: configuration, isSelected: isSelected)
    }
}

private struct EditorRoundButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let isSelected: Bool
    @State private var isHovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .foregroundStyle(isSelected ? Color.white : EditorTheme.primaryText.opacity(isEnabled ? 1 : 0.35))
            .background(Capsule().fill(fill))
            .contentShape(Capsule())
            .onHover { isHovering = $0 && isEnabled }
            .animation(.easeOut(duration: 0.12), value: isHovering)
    }

    private var fill: Color {
        if isSelected { return EditorTheme.accent }
        if configuration.isPressed { return EditorTheme.controlFillHover }
        return isHovering ? EditorTheme.controlFill : .clear
    }
}
