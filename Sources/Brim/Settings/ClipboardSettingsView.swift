// ClipboardSettingsView.swift
// Brim
//
// "Clipboard" tab of the Preferences window: copy-on-selection behavior,
// transparency preservation, resolution handling, and the island clipboard library.

import SwiftUI

struct ClipboardSettingsView: View {

    @State private var copyAfterSelection = AppSettings.shared.copyAfterSelection
    @State private var preserveTransparency = AppSettings.shared.preserveTransparency
    @State private var copyAtOriginalResolution = AppSettings.shared.copyAtOriginalResolution

    var body: some View {
        Group {
            Section {
                Toggle("Copy automatically after selection", isOn: $copyAfterSelection)
                    .onChange(of: copyAfterSelection) { _, newValue in
                        AppSettings.shared.copyAfterSelection = newValue
                    }

                Toggle("Preserve transparency", isOn: $preserveTransparency)
                    .onChange(of: preserveTransparency) { _, newValue in
                        AppSettings.shared.preserveTransparency = newValue
                    }

                Toggle("Copy at original resolution", isOn: $copyAtOriginalResolution)
                    .onChange(of: copyAtOriginalResolution) { _, newValue in
                        AppSettings.shared.copyAtOriginalResolution = newValue
                    }
            } header: {
                Text("Copying captures")
            }
            ClipboardLibrarySettingsSection()
            ClipboardPrivacySettingsSection()
        }
    }
}
