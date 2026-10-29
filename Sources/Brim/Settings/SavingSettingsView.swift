// SavingSettingsView.swift
// Brim
//
// "Saving" tab of the Preferences window: default file format, JPG quality,
// default save folder, auto-save, and file-naming preferences.

import AppKit
import SwiftUI

struct SavingSettingsView: View {

    @State private var defaultImageFormat = AppSettings.shared.defaultImageFormat
    @State private var jpgQuality = AppSettings.shared.jpgQuality
    @State private var defaultSaveFolder = AppSettings.shared.defaultSaveFolder
    @State private var autoSave = AppSettings.shared.autoSave
    @State private var rememberLastSaveLocation = AppSettings.shared.rememberLastSaveLocation
    @State private var fileNamePrefix = AppSettings.shared.fileNamePrefix
    @State private var includeDateInFileName = AppSettings.shared.includeDateInFileName

    var body: some View {
        Group {
            Section {
                Picker("Default format", selection: $defaultImageFormat) {
                    Text("PNG").tag("png")
                    Text("JPG").tag("jpg")
                }
                .onChange(of: defaultImageFormat) { _, newValue in
                    AppSettings.shared.defaultImageFormat = newValue
                }

                LabeledContent("JPG Quality") {
                    Slider(value: $jpgQuality, in: 0 ... 1) {
                        Text("JPG Quality")
                    } minimumValueLabel: {
                        Text("Low")
                    } maximumValueLabel: {
                        Text("High")
                    }
                    .labelsHidden()
                    .frame(maxWidth: 260)
                    .onChange(of: jpgQuality) { _, newValue in
                        AppSettings.shared.jpgQuality = newValue
                    }
                }
                .disabled(defaultImageFormat != "jpg")
            } header: {
                Text("Format")
            }

            Section {
                LabeledContent {
                    Button("Choose…") { chooseFolder() }
                } label: {
                    Text("Save folder")
                    Text(defaultSaveFolder?.path ?? "Not set (uses Desktop)")
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Toggle("Save screenshots automatically to that folder", isOn: $autoSave)
                    .onChange(of: autoSave) { _, newValue in
                        AppSettings.shared.autoSave = newValue
                    }

                Toggle("Remember last save location", isOn: $rememberLastSaveLocation)
                    .onChange(of: rememberLastSaveLocation) { _, newValue in
                        AppSettings.shared.rememberLastSaveLocation = newValue
                    }
            } header: {
                Text("Location")
            }

            Section {
                TextField("File name prefix", text: $fileNamePrefix)
                    .onChange(of: fileNamePrefix) { _, newValue in
                        AppSettings.shared.fileNamePrefix = newValue
                    }

                Toggle("Include date in file name", isOn: $includeDateInFileName)
                    .onChange(of: includeDateInFileName) { _, newValue in
                        AppSettings.shared.includeDateInFileName = newValue
                    }
            } header: {
                Text("File name")
            }
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if let current = defaultSaveFolder {
            panel.directoryURL = current
        }

        guard panel.runModal() == .OK, let url = panel.url else { return }
        defaultSaveFolder = url
        AppSettings.shared.defaultSaveFolder = url
    }
}
