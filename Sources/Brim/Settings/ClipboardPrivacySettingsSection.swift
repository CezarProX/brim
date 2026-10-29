// ClipboardPrivacySettingsSection.swift
// Brim
//
// Privacy controls for the clipboard history: password skipping, link cleaning, clear on quit,
// excluded apps and the timed clear of the Mac clipboard.

import AppKit
import SwiftUI

struct ClipboardPrivacySettingsSection: View {
    @State private var tick = 0
    @State private var newBundleID = ""
    private let settings = AppSettings.shared
    private var binder: SettingBinder { SettingBinder(settings: settings, refresh: { tick += 1 }) }

    var body: some View {
        let _ = tick
        Group {
            privacy
            excludedApps
            autoClear
        }
    }

    private var privacy: some View {
        Section {
            Toggle("Skip passwords", isOn: binder.bind(\.clipboardSkipPasswords))
            Toggle("Clean links when copying from history", isOn: binder.bind(\.clipboardCleanLinksOnCopy))
            Toggle("Clean links as they are copied", isOn: binder.bind(\.clipboardCleanLinksOnCapture))
            Toggle("Clear history when Brim quits", isOn: binder.bind(\.clipboardClearOnQuit))
        } header: { Text("Privacy") } footer: {
            Text("Skip passwords ignores items marked secret or temporary and anything copied from a password manager. Cleaning removes tracking parameters such as utm_*, fbclid and gclid. Pinned entries survive clearing. Everything stays on this Mac.")
        }
    }

    private var excludedApps: some View {
        Section {
            ForEach(settings.clipboardExcludedApps, id: \.self) { bundleID in
                HStack {
                    Text(Self.appName(bundleID))
                    Text(bundleID).font(.footnote).foregroundStyle(.secondary)
                    Spacer()
                    Button { remove(bundleID) } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless).help("Stop excluding \(bundleID)")
                }
            }
            HStack {
                Menu("Add running app") {
                    ForEach(runningApps(), id: \.bundleID) { app in
                        Button(app.name) { add(app.bundleID) }
                    }
                }.fixedSize()
                TextField("Bundle ID", text: $newBundleID).textFieldStyle(.roundedBorder)
                    .onSubmit { add(newBundleID); newBundleID = "" }
                Button("Add") { add(newBundleID); newBundleID = "" }
                    .disabled(newBundleID.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } header: { Text("Excluded apps") } footer: {
            Text("Copies made while one of these apps is in front are never saved.")
        }
    }

    private var autoClear: some View {
        Section {
            Picker("Clear Mac clipboard after", selection: binder.bind(\.clipboardAutoClearSeconds)) {
                Text("Never").tag(0)
                Text("30 seconds").tag(30)
                Text("1 minute").tag(60)
                Text("5 minutes").tag(300)
            }
            Toggle("Only for sensitive items", isOn: binder.bind(\.clipboardAutoClearOnlySensitive))
                .disabled(settings.clipboardAutoClearSeconds == 0)
        } header: { Text("Clipboard") } footer: {
            Text("Empties what you can paste, not the history.")
        }
    }

    private func add(_ raw: String) {
        let id = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, !settings.clipboardExcludedApps.contains(id) else { return }
        settings.clipboardExcludedApps = settings.clipboardExcludedApps + [id]
        tick += 1
    }

    private func remove(_ id: String) {
        settings.clipboardExcludedApps = settings.clipboardExcludedApps.filter { $0 != id }
        tick += 1
    }

    private func runningApps() -> [(name: String, bundleID: String)] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.activationPolicy == .regular, let id = app.bundleIdentifier,
                  id != Bundle.main.bundleIdentifier, !settings.clipboardExcludedApps.contains(id) else { return nil }
            return (app.localizedName ?? id, id)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func appName(_ bundleID: String) -> String {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            .map { FileManager.default.displayName(atPath: $0.path) } ?? bundleID
    }
}
