// StudioInspector.swift
// Brim
//
// Options for the selected timeline item (clip speed, zoom level / focus / instant, hidden-area
// style), and the pointer panel behind the header's pointer button.

import SwiftUI

struct StudioInspector: View {
    @ObservedObject var model: StudioModel

    var body: some View {
        if let clip = model.selectedClip {
            card(title: "Clip", symbol: "film") { clipOptions(clip) }
        } else if let zoom = model.selectedZoom {
            card(title: "Zoom", symbol: "plus.magnifyingglass") { zoomOptions(zoom) }
        } else if let area = model.selectedHiddenArea {
            card(title: "Hidden area", symbol: "eye.slash") { hiddenOptions(area) }
        }
    }

    private func card<Content: View>(title: LocalizedStringKey, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(title, systemImage: symbol).font(.system(size: 13, weight: .semibold))
                Spacer()
                Button { model.deleteSelection() } label: { Image(systemName: "trash") }
                    .buttonStyle(.plain).foregroundStyle(StudioTheme.secondary)
                    .disabled(!model.canDelete)
                    .help("Delete the selected clip, zoom or hidden area")
            }
            content()
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(StudioTheme.panel))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(StudioTheme.hairline))
    }

    private func clipOptions(_ clip: TimelineClip) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Speed").font(.system(size: 12, weight: .medium)).foregroundStyle(StudioTheme.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                ForEach(TimelineClip.speedChoices, id: \.self) { speed in
                    let selected = abs(clip.speed - speed) < 0.001
                    Button { model.setSpeed(speed) } label: {
                        Text(StudioTheme.multiplier(speed)).font(.system(size: 11, weight: .semibold)).monospacedDigit()
                            .frame(maxWidth: .infinity).frame(height: 26)
                            .background(RoundedRectangle(cornerRadius: 7).fill(selected ? StudioTheme.accent : StudioTheme.well))
                            .foregroundStyle(selected ? .white : StudioTheme.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            Text("\(StudioTheme.timecode(clip.outputDuration)) " + L10n.tr("long"))
                .font(.system(size: 11)).monospacedDigit().foregroundStyle(StudioTheme.tertiary)
        }
    }

    private func zoomOptions(_ zoom: ZoomSegment) -> some View {
        let id = zoom.id
        let isFollowing = zoom.focus == .cursor
        return VStack(alignment: .leading, spacing: 12) {
            StudioSliderRow(title: "Zoom", value: Binding(get: { zoom.scale },
                                                         set: { value in model.updateZoom(id, coalesce: "zoom-scale") { $0.scale = value } }),
                            range: ZoomSegment.scaleRange, format: StudioTheme.multiplier)
            Picker("Focus", selection: Binding(get: { isFollowing }, set: { follow in
                model.updateZoom(id) { segment in
                    if follow { segment.focus = .cursor } else {
                        let p = model.track.position(at: segment.start + 0.5) ?? CGPoint(x: 0.5, y: 0.5)
                        segment.focus = .fixed(x: p.x, y: p.y)
                    }
                }
            })) {
                Text("Follow pointer").tag(true)
                Text("Fixed").tag(false)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Toggle(isOn: Binding(get: { zoom.instant }, set: { value in model.updateZoom(id) { $0.instant = value } })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Instant").font(.system(size: 12, weight: .medium))
                    Text("Cuts straight into this zoom and back out instead of easing in and out.")
                        .font(.system(size: 10)).foregroundStyle(StudioTheme.tertiary).fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.switch).controlSize(.mini)
        }
    }

    private func hiddenOptions(_ area: HiddenArea) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Style", selection: Binding(get: { area.kind }, set: { kind in model.updateHiddenArea(area.id) { $0.kind = kind } })) {
                Text("Blur").tag(HiddenArea.Kind.blur)
                Text("Pixelate").tag(HiddenArea.Kind.pixelate)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Text("Blur, pixelate or cover anything the video should not show.")
                .font(.system(size: 11)).foregroundStyle(StudioTheme.tertiary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Pointer look: visibility, size, smoothing, idle hiding and click ripples.
struct StudioPointerPanel: View {
    @ObservedObject var model: StudioModel

    private func cursor<T: Equatable>(_ path: WritableKeyPath<StudioCursorStyle, T>, _ key: String) -> Binding<T> {
        Binding(get: { model.edit.style.cursor[keyPath: path] },
                set: { value in model.change("cursor-\(key)") { $0.style.cursor[keyPath: path] = value } })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            StudioSectionTitle(title: "Pointer")
            Toggle("Show pointer", isOn: cursor(\.isVisible, "visible")).toggleStyle(.switch).controlSize(.small)
            Group {
                StudioSliderRow(title: "Size", value: cursor(\.size, "size"), range: StudioCursorStyle.sizeRange,
                                format: StudioTheme.multiplier)
                StudioSliderRow(title: "Smoothing", value: cursor(\.smoothing, "smoothing"))
                Toggle(isOn: cursor(\.hidesWhenIdle, "idle")) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Hide when idle").font(.system(size: 12, weight: .medium))
                        Text("Fades the cursor out while it rests, and back in just before it moves.")
                            .font(.system(size: 10)).foregroundStyle(StudioTheme.tertiary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .toggleStyle(.switch).controlSize(.small)
                Toggle(isOn: cursor(\.clickRipple, "ripple")) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Click highlights").font(.system(size: 12, weight: .medium))
                        Text("Draws a ripple where you clicked.").font(.system(size: 10)).foregroundStyle(StudioTheme.tertiary)
                    }
                }
                .toggleStyle(.switch).controlSize(.small)
            }
            .disabled(!model.edit.style.cursor.isVisible)
        }
        .environment(\.colorScheme, .dark)
    }
}
