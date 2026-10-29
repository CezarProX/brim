// GeneralSettingsView.swift
// Brim
//
// "General" tab of the Preferences window: launch at login, Dock visibility,
// notifications/sound, and auto-close behavior after copy/save.

import AppKit
import ServiceManagement
import SwiftUI

struct GeneralSettingsView: View {

    @State private var launchAtLogin = AppSettings.shared.launchAtLogin
    @State private var showInDock = AppSettings.shared.showInDock
    @State private var launchAtLoginErrorMessage: String?
    @State private var notchShelfEnabled = AppSettings.shared.notchShelfEnabled

    var body: some View {
        Group {
            Section {
                Toggle(isOn: $notchShelfEnabled) {
                    Text("Enable Brim at the notch")
                    Text("Opens only when you hover over the notch and collapses when you move away. Keeps up to 20 recent images (150 MB) on this Mac.")
                }
                .onChange(of: notchShelfEnabled) { _, value in
                    AppSettings.shared.notchShelfEnabled = value
                    NotchShelfController.shared.settingsChanged()
                }
                .settingsAnchor("general.notch")
                IslandTourSettingsRow(islandEnabled: notchShelfEnabled)
            } header: {
                Text("Notch")
            }
            LanguageSettingsSection()
            Section {
                Toggle("Launch Brim at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        setLaunchAtLogin(newValue)
                    }
                Toggle("Show Brim in the Dock", isOn: $showInDock)
                    .onChange(of: showInDock) { _, newValue in
                        AppSettings.shared.showInDock = newValue
                        NSApp.setActivationPolicy(newValue ? .regular : .accessory)
                    }
            } header: {
                Text("Startup")
            } footer: {
                if let launchAtLoginErrorMessage { SettingsFootnote(launchAtLoginErrorMessage) }
            }
        }
        .onAppear(perform: syncLaunchAtLoginStatus)
    }

    /// `SMAppService` is the actual source of truth for the login-item
    /// state, so reflect it rather than trusting a possibly-stale toggle.
    private func syncLaunchAtLoginStatus() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            AppSettings.shared.launchAtLogin = enabled
            launchAtLoginErrorMessage = nil
        } catch {
            // Registration can legitimately fail for unbundled/unsigned dev
            // builds — don't crash, just surface it and reflect reality.
            launchAtLoginErrorMessage =
                "Couldn't update login item (this can fail for dev builds outside /Applications): \(error.localizedDescription)"
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
