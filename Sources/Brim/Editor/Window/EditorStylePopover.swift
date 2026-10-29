// EditorStylePopover.swift
// Brim
//
// Colour, stroke width, text size and outline/fill for annotations. Edits
// `session.currentStyle`, which also restyles the selected annotation.

import SwiftUI

struct EditorStylePopover: View {
    @ObservedObject var model: ScreenshotEditorModel

    static let swatches: [NSColor] = [
        .systemRed, .systemOrange, .systemYellow, .systemGreen, .systemBlue, .systemPurple, .systemPink, .white, .black
    ]

    var body: some View {
        let _ = model.revision
        VStack(alignment: .leading, spacing: 14) {
            EditorSectionHeader(title: L10n.tr("Colour"))
            HStack(spacing: 6) {
                ForEach(Self.swatches, id: \.self) { color in swatch(color) }
                ColorPicker("", selection: colorBinding, supportsOpacity: false).labelsHidden().frame(width: 24)
            }
            CommitOnReleaseSlider(title: L10n.tr("Stroke"), value: widthBinding, range: 1...12, unit: "pt")
            CommitOnReleaseSlider(title: L10n.tr("Text size"), value: fontBinding, range: 12...96, unit: "pt")
            Toggle(L10n.tr("Fill rectangles and ellipses"), isOn: fillBinding)
                .toggleStyle(.switch).controlSize(.small)
                .font(EditorTheme.rowTitle)
        }
        .padding(16)
        .frame(width: 300)
        .environment(\.colorScheme, .dark)
    }

    private func swatch(_ color: NSColor) -> some View {
        let selected = Self.matches(color, model.annotationStyle.color)
        return Button { update { $0.color = color } } label: {
            Circle().fill(Color(nsColor: color))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.25)))
                .padding(3)
                .overlay(Circle().strokeBorder(Color.white.opacity(selected ? 0.9 : 0), lineWidth: 1.5))
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(color.accessibilityName)
    }

    private func update(_ change: (inout AnnotationStyle) -> Void) {
        var style = model.annotationStyle
        change(&style)
        model.annotationStyle = style
    }

    private var colorBinding: Binding<Color> {
        Binding(get: { Color(nsColor: model.annotationStyle.color) },
                set: { newValue in update { $0.color = NSColor(newValue) } })
    }

    private var widthBinding: Binding<Double> {
        Binding(get: { Double(model.annotationStyle.lineWidth) },
                set: { newValue in update { $0.lineWidth = CGFloat(newValue) } })
    }

    private var fontBinding: Binding<Double> {
        Binding(get: { Double(model.annotationStyle.fontSize) },
                set: { newValue in update { $0.fontSize = CGFloat(newValue) } })
    }

    private var fillBinding: Binding<Bool> {
        Binding(get: { model.annotationStyle.isFilled }, set: { newValue in update { $0.isFilled = newValue } })
    }

    static func matches(_ a: NSColor, _ b: NSColor) -> Bool {
        guard let a = a.usingColorSpace(.deviceRGB), let b = b.usingColorSpace(.deviceRGB) else { return false }
        return abs(a.redComponent - b.redComponent) < 0.01 && abs(a.greenComponent - b.greenComponent) < 0.01
            && abs(a.blueComponent - b.blueComponent) < 0.01
    }
}

/// A labelled slider that shows its value live but writes it back only when
/// the drag ends, so restyling a selected annotation is one undo step.
struct CommitOnReleaseSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let unit: String
    @State private var draft: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(EditorTheme.rowTitle).foregroundStyle(EditorTheme.primaryText)
                Spacer()
                Text(verbatim: "\(Int((draft ?? value).rounded())) \(unit)")
                    .font(.system(size: 11).monospacedDigit()).foregroundStyle(EditorTheme.secondaryText)
            }
            Slider(
                value: Binding(get: { draft ?? value }, set: { draft = $0 }),
                in: range, step: 1,
                onEditingChanged: { editing in
                    guard !editing, let final = draft else { return }
                    value = final
                    draft = nil
                }
            )
            .controlSize(.small)
        }
    }
}
