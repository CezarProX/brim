// StudioTheme.swift
// Brim
//
// Colours, metrics and small shared controls for the Studio editor (dark).

import SwiftUI

enum StudioTheme {
    static let window = Color(red: 0.086, green: 0.086, blue: 0.098)
    static let sidebar = Color(red: 0.118, green: 0.118, blue: 0.133)
    static let panel = Color(red: 0.145, green: 0.145, blue: 0.161)
    static let well = Color.white.opacity(0.06)
    static let hairline = Color.white.opacity(0.08)
    static let primary = Color.white
    static let secondary = Color.white.opacity(0.6)
    static let tertiary = Color.white.opacity(0.38)
    static let accent = Color(red: 0.32, green: 0.56, blue: 1)
    static let zoom = Color(red: 0.55, green: 0.42, blue: 1)
    static let hidden = Color(red: 1, green: 0.62, blue: 0.25)
    static let playhead = Color(red: 1, green: 0.84, blue: 0.3)
    static let record = Color(red: 1, green: 0.27, blue: 0.23)

    static let sidebarWidth: CGFloat = 268
    static let headerHeight: CGFloat = 52

    /// "00:03.0"
    static func timecode(_ seconds: Double) -> String {
        let clamped = max(0, seconds)
        let tenths = Int((clamped * 10).rounded(.down))
        return String(format: "%02d:%02d.%d", tenths / 600, (tenths / 10) % 60, tenths % 10)
    }

    /// "1.5×"
    static func multiplier(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        let text = rounded == rounded.rounded() ? String(format: "%.1f", rounded) : String(format: "%g", rounded)
        return text + "×"
    }
}

/// A square icon button with a hover wash, used by the toolbar and transport.
struct StudioIconButton: View {
    let symbol: String
    let help: LocalizedStringKey
    var size: CGFloat = 30
    var weight: Font.Weight = .medium
    var isOn = false
    var isEnabled = true
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.46, weight: weight))
                .frame(width: size, height: size)
                .foregroundStyle(isOn ? StudioTheme.accent : (isEnabled ? StudioTheme.primary.opacity(0.88) : StudioTheme.tertiary))
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isOn ? StudioTheme.accent.opacity(0.18) : (hovering && isEnabled ? Color.white.opacity(0.08) : .clear)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { hovering = $0 }
        .help(help)
    }
}

/// Section heading in the sidebar.
struct StudioSectionTitle: View {
    let title: LocalizedStringKey

    var body: some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(StudioTheme.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// "Padding ——●—— 6%"
struct StudioSliderRow: View {
    let title: LocalizedStringKey
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    var format: (Double) -> String = { "\(Int(($0 * 100).rounded()))%" }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(StudioTheme.secondary)
                Spacer()
                Text(format(value)).font(.system(size: 12, weight: .medium)).monospacedDigit().foregroundStyle(StudioTheme.secondary)
            }
            Slider(value: $value, in: range).controlSize(.small).tint(StudioTheme.accent)
        }
    }
}
