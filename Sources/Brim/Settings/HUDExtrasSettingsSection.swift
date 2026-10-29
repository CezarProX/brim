// HUDExtrasSettingsSection.swift
// Brim
//
// Downloads, recordings, AirPods, display target, capture thumbnail and "notify me". Self-contained;
// the integrator adds it under the HUDs pane.

import SwiftUI

struct HUDExtrasSettingsSection: View {
    @State private var ring = AppSettings.shared.downloadProgressRing
    @State private var trashDMG = AppSettings.shared.trashDiskImageAfterInstall
    @State private var recordingCard = AppSettings.shared.recordingResultCard
    @State private var airPods = AppSettings.shared.hudAirPodsCard
    @State private var notify = AppSettings.shared.notifyLongTasks
    @State private var target = AppSettings.shared.hudDisplayTarget
    @State private var hideThumbnail = CaptureThumbnailPreference.currentlyHidden()
    @State private var thumbnailNote = false

    var body: some View {
        Group {
            group("Downloads") {
                Toggle("Progress ring and time left", isOn: bind($ring, \.downloadProgressRing))
                Toggle("Move a disk image (.dmg) to the Trash after install", isOn: bind($trashDMG, \.trashDiskImageAfterInstall))
                    .onChange(of: trashDMG) { _, _ in DiskImageTrasher.shared.refresh() }
                Text("Needs the Downloads live activity (Live Activities pane), which asks for Downloads folder access. Only .dmg files in Downloads are ever trashed, and only after you eject their volume. Chrome and Firefox do not tell the total size, so those show the size so far instead of a time.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            group("Recordings and notifications") {
                Toggle("Result card after a screen recording", isOn: bind($recordingCard, \.recordingResultCard))
                Toggle("AirPods card with battery levels when they connect", isOn: bind($airPods, \.hudAirPodsCard))
                Toggle("Notify me when a long download or recording finishes", isOn: bind($notify, \.notifyLongTasks))
                    .onChange(of: notify) { _, on in if on { LongTaskNotifier.shared.requestAuthorizationIfNeeded() } }
            }
            group("Displays") {
                Picker("Show compact HUDs on", selection: $target) {
                    ForEach(HUDDisplayTarget.allCases) { Text($0.title).tag($0) }
                }
                .onChange(of: target) { _, value in AppSettings.shared.hudDisplayTarget = value }
            }
            group("macOS screenshots") {
                Toggle("Hide the macOS capture thumbnail", isOn: $hideThumbnail)
                    .onChange(of: hideThumbnail) { _, hidden in
                        thumbnailNote = CaptureThumbnailPreference.setHidden(hidden)
                    }
                Text(thumbnailNote
                     ? "Saved. macOS applies this the next time the screenshot service restarts (log out and in, or run killall screencaptureui)."
                     : "Writes the com.apple.screencaptureui “show-thumbnail” default. It takes effect after the screenshot service restarts.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private func bind(_ state: Binding<Bool>, _ keyPath: ReferenceWritableKeyPath<AppSettings, Bool>) -> Binding<Bool> {
        Binding(get: { state.wrappedValue }, set: { value in
            state.wrappedValue = value
            AppSettings.shared[keyPath: keyPath] = value
        })
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
      SettingsSection(title) { content() }
    }
}
