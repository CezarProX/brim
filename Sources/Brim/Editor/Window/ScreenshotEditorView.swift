// ScreenshotEditorView.swift
// Brim
//
// Root of the "Edit screenshot" window: collapsible sidebar on the left;
// the tool strip above the canvas on the right. Title-bar controls (sidebar
// toggle, share, Done) live in the window's NSToolbar.

import SwiftUI

struct ScreenshotEditorView: View {
    @ObservedObject var model: ScreenshotEditorModel

    var body: some View {
        HStack(spacing: 0) {
            if model.isSidebarVisible {
                EditorSidebarView(model: model)
                    .transition(.move(edge: .leading).combined(with: .opacity))
                Rectangle().fill(EditorTheme.separator).frame(width: 1)
            }
            VStack(spacing: 0) {
                toolStrip
                    .padding(.vertical, 10)
                EditorCanvasRepresentable(host: model.canvasHost)
            }
            .background(EditorTheme.canvasBackground)
        }
        .background(EditorTheme.windowBackground)
        .environment(\.colorScheme, .dark)
        .animation(.easeInOut(duration: 0.22), value: model.isSidebarVisible)
    }

    /// Centred when it fits; scrolls sideways in a narrow window.
    private var toolStrip: some View {
        ViewThatFits(in: .horizontal) {
            EditorToolStripView(model: model).padding(.horizontal, 12)
            ScrollView(.horizontal, showsIndicators: false) {
                EditorToolStripView(model: model).padding(.horizontal, 12)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct EditorCanvasRepresentable: NSViewRepresentable {
    let host: EditorCanvasHostView

    func makeNSView(context: Context) -> EditorCanvasHostView { host }
    func updateNSView(_ nsView: EditorCanvasHostView, context: Context) {}
}
