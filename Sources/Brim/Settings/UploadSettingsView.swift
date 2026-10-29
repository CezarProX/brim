// UploadSettingsView.swift
// Brim
//
// "Upload" tab of the Preferences window: auto-upload behavior and the
// upload service endpoint.

import SwiftUI

struct UploadSettingsView: View {

    @State private var autoUpload = AppSettings.shared.autoUpload
    @State private var autoCopyLink = AppSettings.shared.autoCopyLink
    @State private var uploadServiceURL = AppSettings.shared.uploadServiceURL

    var body: some View {
        Group {
            Section {
                Toggle("Automatically upload screenshots", isOn: $autoUpload)
                    .onChange(of: autoUpload) { _, newValue in
                        AppSettings.shared.autoUpload = newValue
                    }

                Toggle("Automatically copy link after upload", isOn: $autoCopyLink)
                    .onChange(of: autoCopyLink) { _, newValue in
                        AppSettings.shared.autoCopyLink = newValue
                    }
                TextField("Upload service URL", text: $uploadServiceURL)
                    .onChange(of: uploadServiceURL) { _, newValue in
                        AppSettings.shared.uploadServiceURL = newValue
                    }
                    .settingsAnchor("upload.service")
            } header: {
                Text("Upload")
            }
        }
    }
}
