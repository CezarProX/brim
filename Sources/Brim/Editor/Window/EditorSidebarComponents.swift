// EditorSidebarComponents.swift
// Brim
//
// Small building blocks for the editor sidebar: percentage sliders, chip
// rows, the 3x3 alignment grid, and swatch / preview / preset thumbnails
// rendered with the same `StyledCanvasRenderer` as the export.

import SwiftUI

struct EditorPercentSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    /// Multiplier from the stored value to the percentage shown.
    let displayScale: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                EditorSectionHeader(title: title)
                Text(verbatim: "\(Int((value * displayScale).rounded()))%")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(EditorTheme.primaryText)
            }
            Slider(value: $value, in: range).controlSize(.small)
        }
    }
}

/// Equal-width segmented chips (Square / Small / Medium / Large).
struct EditorChipRow<Option: Hashable>: View {
    let options: [Option]
    @Binding var selection: Option
    let title: (Option) -> String

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.self) { option in
                let selected = option == selection
                Button { selection = option } label: {
                    Text(verbatim: title(option))
                        .font(.system(size: 11, weight: .medium))
                        .frame(maxWidth: .infinity, minHeight: 26)
                        .foregroundStyle(selected ? Color.white : EditorTheme.primaryText)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(selected ? EditorTheme.accent : EditorTheme.controlFill))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Nine dots; the selected one marks where the content sits.
struct EditorAlignmentGrid: View {
    @Binding var selection: ContentAlignment
    private static let rows: [[ContentAlignment]] = [
        [.topLeading, .top, .topTrailing], [.leading, .center, .trailing], [.bottomLeading, .bottom, .bottomTrailing]
    ]

    var body: some View {
        VStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: 3) {
                    ForEach(Self.rows[row], id: \.self) { alignment in
                        Button { selection = alignment } label: {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(alignment == selection ? EditorTheme.accent : EditorTheme.controlFill)
                                .frame(width: 18, height: 14)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(alignment.rawValue)
                    }
                }
            }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.03)))
    }
}

struct GradientSwatch: View {
    let preset: GradientPreset

    var body: some View {
        if let image = SidebarThumbnails.gradient(preset) {
            Image(decorative: image, scale: 2).resizable()
        } else {
            Color.gray
        }
    }
}

/// A wide preview of an image-based background.
struct BackgroundPreview: View {
    let background: CanvasBackground

    var body: some View {
        Group {
            if let image = SidebarThumbnails.backdrop(background) {
                Image(decorative: image, scale: 2).resizable().aspectRatio(contentMode: .fill)
            } else {
                EditorTheme.controlFill
            }
        }
        .frame(height: 96)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: EditorTheme.tileCorner, style: .continuous))
    }
}

/// A miniature of a whole look: background, padding, corners, shadow.
struct PresetThumbnail: View {
    let style: CanvasStyle

    var body: some View {
        if let image = SidebarThumbnails.preset(style) {
            Image(decorative: image, scale: 2).resizable().aspectRatio(contentMode: .fill)
        } else {
            EditorTheme.controlFill
        }
    }
}

@MainActor
enum SidebarThumbnails {
    private static var cache: [String: CGImage] = [:]

    static func gradient(_ preset: GradientPreset) -> CGImage? {
        cached("g|\(preset.id)") {
            guard let ctx = StyledCanvasRenderer.makeContext(size: CGSize(width: 96, height: 96)) else { return nil }
            StyledCanvasRenderer.drawGradient(preset, in: ctx, rect: CGRect(x: 0, y: 0, width: 96, height: 96))
            return ctx.makeImage()
        }
    }

    static func backdrop(_ background: CanvasBackground) -> CGImage? {
        cached("b|\(background)") {
            let size = CGSize(width: 480, height: 192)
            guard let ctx = StyledCanvasRenderer.makeContext(size: size) else { return nil }
            StyledCanvasRenderer.drawBackground(BackgroundResolver.resolve(background), in: ctx, rect: CGRect(origin: .zero, size: size))
            return ctx.makeImage()
        }
    }

    /// A 4:3 tile: a light "window" placeholder inside the look.
    static func preset(_ style: CanvasStyle) -> CGImage? {
        cached("p|\(style.hashValue)") {
            var tileStyle = style
            tileStyle.aspect = .classic
            tileStyle.alignment = .center
            if !tileStyle.isEnabled { tileStyle = CanvasStyle(isEnabled: true, background: .solid(RGBAColor(hex: 0x2A2A2E)), padding: 0.14) }
            tileStyle.padding = max(0.12, min(0.2, tileStyle.padding * 1.5))
            let content = CGSize(width: 150, height: 100)
            let layout = StyledCanvasLayout.make(contentSize: content, style: tileStyle).scaled(by: 1.2)
            guard let ctx = StyledCanvasRenderer.makeContext(size: layout.canvasSize) else { return nil }
            StyledCanvasRenderer.drawBackdrop(in: ctx, layout: layout, background: BackgroundResolver.resolve(tileStyle.background))
            StyledCanvasRenderer.drawContent(in: ctx, layout: layout) { ctx, rect in drawPlaceholderWindow(ctx, rect) }
            return ctx.makeImage()
        }
    }

    private static func drawPlaceholderWindow(_ ctx: CGContext, _ rect: CGRect) {
        ctx.setFillColor(CGColor(gray: 0.97, alpha: 1))
        ctx.fill(rect)
        ctx.setFillColor(CGColor(gray: 0.88, alpha: 1))
        ctx.fill(CGRect(x: rect.minX, y: rect.maxY - rect.height * 0.16, width: rect.width, height: rect.height * 0.16))
        ctx.setFillColor(CGColor(gray: 0.8, alpha: 1))
        for (index, width) in [0.62, 0.48, 0.7].enumerated() {
            let y = rect.maxY - rect.height * (0.36 + 0.17 * CGFloat(index))
            ctx.fill(CGRect(x: rect.minX + rect.width * 0.1, y: y, width: rect.width * width, height: rect.height * 0.07))
        }
    }

    private static func cached(_ key: String, make: () -> CGImage?) -> CGImage? {
        if let image = cache[key] { return image }
        guard let image = make() else { return nil }
        if cache.count > 64 { cache.removeAll() }
        cache[key] = image
        return image
    }
}
