// StudioView.swift
// Brim
//
// The Studio editor layout: header (sidebar toggle, title, share, pointer look, Export), the
// style sidebar, the toolbar, the canvas preview, the transport and the timeline.

import SwiftUI

struct StudioView: View {
    @ObservedObject var model: StudioModel
    var trafficLightInset: CGFloat = 78

    var body: some View {
        VStack(spacing: 0) {
            StudioHeader(model: model, leadingInset: trafficLightInset)
            HStack(spacing: 0) {
                if model.sidebarVisible {
                    StudioSidebar(model: model)
                        .frame(width: StudioTheme.sidebarWidth)
                        .background(StudioTheme.sidebar)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    Rectangle().fill(StudioTheme.hairline).frame(width: 1)
                }
                VStack(spacing: 0) {
                    StudioToolbar(model: model)
                    StudioCanvas(model: model)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    StudioTransport(model: model)
                    StudioTimeline(model: model)
                        .frame(height: model.edit.hiddenAreas.isEmpty ? 138 : 168)
                }
                .background(StudioTheme.window)
            }
        }
        .background(StudioTheme.window)
        .environment(\.colorScheme, .dark)
        .animation(.snappy(duration: 0.25), value: model.sidebarVisible)
        .background(StudioKeyCommands(model: model))
    }
}

/// Top bar. The window's traffic lights sit in `leadingInset`.
struct StudioHeader: View {
    @ObservedObject var model: StudioModel
    let leadingInset: CGFloat
    @State private var showsPointer = false
    @State private var showsExport = false

    var body: some View {
        HStack(spacing: 10) {
            Color.clear.frame(width: leadingInset)
            StudioIconButton(symbol: "sidebar.left", help: "Show or hide the sidebar", size: 28, isOn: false) {
                model.sidebarVisible.toggle()
            }
            Text(model.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(StudioTheme.primary)
                .lineLimit(1)
            Spacer(minLength: 12)
            shareButton
            StudioIconButton(symbol: "cursorarrow.motionlines", help: "Pointer and click effects", size: 30, isOn: showsPointer) {
                showsPointer.toggle()
            }
            .popover(isPresented: $showsPointer, arrowEdge: .bottom) {
                StudioPointerPanel(model: model).frame(width: 280).padding(16)
            }
            Button { showsExport.toggle() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.up.on.square").font(.system(size: 12, weight: .semibold))
                    Text("Export").font(.system(size: 13, weight: .semibold))
                }
                .padding(.horizontal, 14).frame(height: 30)
                .background(Capsule().fill(StudioTheme.accent))
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("e", modifiers: .command)
            .help("Render with these settings and save the video file to your recordings folder")
            .popover(isPresented: $showsExport, arrowEdge: .bottom) {
                StudioExportPanel(model: model) { showsExport = false }.frame(width: 300).padding(16)
            }
        }
        .padding(.trailing, 14)
        .frame(height: StudioTheme.headerHeight)
        .background(StudioTheme.window)
        .overlay(alignment: .bottom) { Rectangle().fill(StudioTheme.hairline).frame(height: 1) }
    }

    @ViewBuilder private var shareButton: some View {
        if case .finished(let url) = model.exportState {
            ShareLink(item: url) {
                Image(systemName: "square.and.arrow.up").font(.system(size: 14, weight: .medium))
                    .frame(width: 30, height: 30).foregroundStyle(StudioTheme.primary.opacity(0.88))
            }
            .buttonStyle(.plain)
            .help("Share the exported video")
        } else {
            StudioIconButton(symbol: "square.and.arrow.up", help: "Export, then share", size: 30, isEnabled: !model.isExporting) {
                model.export()
            }
        }
    }
}

/// Keyboard shortcuts that aren't on a visible button.
private struct StudioKeyCommands: View {
    @ObservedObject var model: StudioModel

    var body: some View {
        ZStack {
            Button("") { model.togglePlay() }.keyboardShortcut(.space, modifiers: [])
            Button("") { model.deleteSelection() }.keyboardShortcut(.delete, modifiers: [])
            Button("") { model.step(forward: false) }.keyboardShortcut(.leftArrow, modifiers: [])
            Button("") { model.step(forward: true) }.keyboardShortcut(.rightArrow, modifiers: [])
            Button("") { model.tool = nil; model.selection = nil }.keyboardShortcut(.escape, modifiers: [])
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }
}
