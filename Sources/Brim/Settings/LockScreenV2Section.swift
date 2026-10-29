// LockScreenV2Section.swift
// Brim
//
// Lock screen v2 options: artwork scene, lyrics, edge sliders, keep-awake after locking and the
// status row's per-item toggles. Self-contained; the integrator adds it under the Lock Screen pane.

import SwiftUI

struct LockScreenV2Section: View {
    @State private var artwork = AppSettings.shared.lockScreenArtworkScene
    @State private var lyrics = AppSettings.shared.lockScreenLyrics
    @State private var lockSliders = AppSettings.shared.lockScreenEdgeSliders
    @State private var desktopSliders = AppSettings.shared.desktopEdgeSliders
    @State private var awakeMinutes = AppSettings.shared.lockScreenKeepAwakeMinutes
    @State private var sun = AppSettings.shared.lockSunChipEnabled
    @State private var air = AppSettings.shared.lockAirQualityChipEnabled
    @State private var hidden = AppSettings.shared.lockScreenHiddenStatusItems

    static let statusItems: [(id: String, title: String)] = [
        ("battery", "Battery"), ("calendar", "Next calendar event"), ("weather", "Weather"),
        ("sun", "Sunrise / sunset"), ("air", "Air quality"),
    ]

    var body: some View {
        Group {
            group("Artwork and lyrics") {
                Toggle("Tap the artwork for a fullscreen artwork screen", isOn: bind($artwork, \.lockScreenArtworkScene))
                Toggle("Synced lyrics above the player", isOn: bind($lyrics, \.lockScreenLyrics))
                Text("Lyrics reuse the Media setting “Show lyrics”, which fetches them from lrclib.net over HTTPS. Nothing is sent unless that is on.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            group("Edge sliders") {
                Toggle("Volume and brightness sliders on the lock screen", isOn: bind($lockSliders, \.lockScreenEdgeSliders))
                Toggle("Use edge sliders on the desktop instead of the notch HUD", isOn: bind($desktopSliders, \.desktopEdgeSliders))
                Text("A glass pill on the left screen edge. The first key press shows the wide pill, follow-ups a thin one. Needs the volume and brightness keys to be handled by Brim (Accessibility).")
                    .font(.callout).foregroundStyle(.secondary)
            }
            group("Keep awake") {
                Stepper(value: $awakeMinutes, in: 0...120, step: 5) {
                    Text(awakeMinutes == 0 ? "Don’t keep the screen awake after locking"
                         : "Keep the screen awake \(awakeMinutes) min after locking")
                }
                .onChange(of: awakeMinutes) { _, value in AppSettings.shared.lockScreenKeepAwakeMinutes = value }
            }
            group("Sky chips") {
                Toggle("Next sunrise or sunset", isOn: bind($sun, \.lockSunChipEnabled))
                    .onChange(of: sun) { _, _ in SkyExtrasStore.shared.settingsChanged() }
                Toggle("Air quality index", isOn: bind($air, \.lockAirQualityChipEnabled))
                    .onChange(of: air) { _, _ in SkyExtrasStore.shared.settingsChanged() }
                Text("Opt-in. Sends your rounded Weather location (the city you chose, or your approximate location in Automatic mode) to open-meteo.com over HTTPS, about every 30 minutes. They need Weather set up in the Widgets pane, and stay empty until a lookup succeeds. The status row shows at most four chips.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            group("Status row items") {
                ForEach(Self.statusItems, id: \.id) { item in
                    Toggle(item.title, isOn: Binding(get: { !hidden.contains(item.id) }, set: { on in
                        if on { hidden.remove(item.id) } else { hidden.insert(item.id) }
                        AppSettings.shared.lockScreenHiddenStatusItems = hidden
                    }))
                }
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
