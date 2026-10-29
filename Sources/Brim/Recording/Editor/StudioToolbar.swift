// StudioToolbar.swift
// Brim
//
// Record, crop, hide area, add zoom · undo, redo · split, delete, reset.

import SwiftUI

struct StudioToolbar: View {
    @ObservedObject var model: StudioModel

    var body: some View {
        HStack(spacing: 4) {
            StudioIconButton(symbol: "record.circle", help: "Start a new recording") {
                RecordingController.shared.showBar()
            }
            divider
            StudioIconButton(symbol: "crop", help: "Crop the recording", isOn: model.tool == .crop) {
                model.tool = model.tool == .crop ? nil : .crop
            }
            StudioIconButton(symbol: "eye.slash", help: "Blur, pixelate or cover anything the video should not show.",
                             isOn: model.tool == .hide) {
                model.tool = model.tool == .hide ? nil : .hide
            }
            StudioIconButton(symbol: "plus.magnifyingglass", help: "Add a zoom at the playhead") { model.addZoomAtPlayhead() }
            divider
            StudioIconButton(symbol: "arrow.uturn.backward", help: "Undo", isEnabled: model.history.canUndo) { model.undo() }
                .keyboardShortcut("z", modifiers: .command)
            StudioIconButton(symbol: "arrow.uturn.forward", help: "Redo", isEnabled: model.history.canRedo) { model.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
            divider
            StudioIconButton(symbol: "scissors", help: "Split the clip at the playhead") { model.split() }
                .keyboardShortcut("b", modifiers: .command)
            StudioIconButton(symbol: "trash", help: "Delete the selected clip, zoom or hidden area", isEnabled: model.canDelete) {
                model.deleteSelection()
            }
            StudioIconButton(symbol: "arrow.counterclockwise", help: "Reset all cuts, zooms and hidden areas") { model.resetEdit() }
        }
        .padding(.horizontal, 6)
        .frame(height: 40)
        .background(Capsule().fill(StudioTheme.panel))
        .overlay(Capsule().strokeBorder(StudioTheme.hairline))
        .padding(.top, 12)
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle().fill(StudioTheme.hairline).frame(width: 1, height: 18).padding(.horizontal, 4)
    }
}
