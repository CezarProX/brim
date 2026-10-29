// ClipboardLibrarySettingsSection.swift
// Brim
//
// Settings for the island's clipboard library: smart pinboards, history size and
// retention, and what selecting an entry does. Embedded in ClipboardSettingsView's Form.

import SwiftUI

/// Binds a setting to SwiftUI, refreshing the view when it is written.
@MainActor
struct SettingBinder {
    let settings: AppSettings
    let refresh: () -> Void
    func bind<T>(_ keyPath: ReferenceWritableKeyPath<AppSettings, T>, then: (() -> Void)? = nil) -> Binding<T> {
        Binding(get: { settings[keyPath: keyPath] },
                set: { settings[keyPath: keyPath] = $0; refresh(); then?() })
    }
}

struct ClipboardLibrarySettingsSection: View {
    @State private var tick = 0
    private let settings = AppSettings.shared
    private var binder: SettingBinder { SettingBinder(settings: settings, refresh: { tick += 1 }) }

    var body: some View {
        let _ = tick
        Group {
            pinboards
            history
            selecting
            importSection
        }
    }

    private var pinboards: some View {
        Section {
            ForEach(ClipboardPinboard.allCases) { board in
                Toggle(isOn: Binding(
                    get: { settings.clipboardPinboards.contains(board.rawValue) },
                    set: { on in
                        var next = settings.clipboardPinboards.filter { $0 != board.rawValue }
                        if on { next.append(board.rawValue) }
                        settings.clipboardPinboards = next
                        tick += 1
                    })) { Label(board.title, systemImage: board.symbol) }
            }
        } header: { Text("Smart pinboards") } footer: {
            Text("Each enabled pinboard becomes a tab in the island’s clipboard library and gathers matching clips automatically.")
        }
    }

    private var history: some View {
        Section("History") {
            Toggle("No limit (up to the 100 MB size cap)", isOn: Binding(
                get: { settings.clipboardHistoryLimit == 0 },
                set: { settings.clipboardHistoryLimit = $0 ? 0 : 100; tick += 1; ClipboardStore.shared.pruneExpired() }))
            if settings.clipboardHistoryLimit > 0 {
                HStack {
                    Text("History limit")
                    Slider(value: Binding(
                        get: { Double(settings.clipboardHistoryLimit) },
                        set: { settings.clipboardHistoryLimit = Int($0.rounded() / 10) * 10; tick += 1 }),
                        in: 10...500, step: 10) { editing in if !editing { ClipboardStore.shared.pruneExpired() } }
                    Text("\(settings.clipboardHistoryLimit)").monospacedDigit().frame(width: 34, alignment: .trailing)
                }
            }
            Picker("Keep entries for", selection: binder.bind(\.clipboardKeepFor, then: { ClipboardStore.shared.pruneExpired() })) {
                ForEach(ClipboardKeepFor.allCases) { Text($0.title).tag($0) }
            }
            Toggle("Reject duplicates (move the existing entry to the top)", isOn: binder.bind(\.clipboardRejectDuplicates))
            Picker("Pinned entries", selection: binder.bind(\.clipboardPinnedPlacement)) {
                ForEach(ClipboardPinnedPlacement.allCases) { Text($0.title).tag($0) }
            }
        }
    }

    private var selecting: some View {
        Section {
            Toggle("Paste on select", isOn: binder.bind(\.clipboardPasteOnSelect, then: {
                if settings.clipboardPasteOnSelect, !ClipboardPaster.isAccessibilityTrusted {
                    ClipboardPaster.requestAccessibility()
                }
            }))
            if settings.clipboardPasteOnSelect {
                Label(ClipboardPaster.isAccessibilityTrusted
                      ? "Accessibility is on. Choosing an entry pastes it into the app you were using."
                      : "Turn on Brim in System Settings > Privacy & Security > Accessibility to paste. Until then, choosing an entry only copies it.",
                      systemImage: ClipboardPaster.isAccessibilityTrusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Toggle("Copy + favorite (choosing an entry also pins it)", isOn: binder.bind(\.clipboardCopyAndFavorite))
            Toggle("Start typing in search when the library opens", isOn: binder.bind(\.clipboardAutoFocusSearch))
            Toggle("Open the clipboard with ⌥⇧Space", isOn: binder.bind(\.clipboardShortcutEnabled, then: {
                ClipboardFeature.shared.applySettings()
            }))
        } header: { Text("Choosing an entry") }
    }

    private var importSection: some View {
        ClipboardImportRow()
    }
}

/// "Import from another app" (Maccy, Clipy, Raycast, Paste). Read-only; reports plainly when nothing could be imported.
private struct ClipboardImportRow: View {
    @State private var message: String?
    @State private var working = false

    var body: some View {
        Section {
            HStack {
                Menu(working ? "Importing…" : "Import from…") {
                    ForEach(ClipboardImportSource.allCases) { source in
                        Button(source.title) { runImport(source) }
                    }
                }
                .fixedSize().disabled(working)
                if let message { Text(message).font(.footnote).foregroundStyle(.secondary) }
            }
        } header: { Text("Import") } footer: {
            Text("Copies text history from Maccy, Clipy, Raycast or Paste when their files can be read. Their files are only read, never changed. Raycast and Paste may protect their history; Brim says so instead of guessing.")
        }
    }

    private func runImport(_ source: ClipboardImportSource) {
        working = true
        Task { @MainActor in
            let result = await Task.detached { ClipboardImporters.importHistory(from: source) }.value
            switch result {
            case .unavailable(let reason): message = reason
            case .items(let items):
                let added = ClipboardStore.shared.importItems(items)
                message = added == 0 ? "Nothing new to import." : "Imported \(added) \(added == 1 ? "entry" : "entries") from \(source.title)."
            }
            working = false
        }
    }
}
