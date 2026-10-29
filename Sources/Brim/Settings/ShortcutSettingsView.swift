// ShortcutSettingsView.swift
// Brim
//
// The unified "Shortcuts" pane: every global shortcut in the app in one list, each with a recorder,
// conflict detection (against our own shortcuts and macOS-reserved combos) and a reset button.

import SwiftUI

struct ShortcutSettingsView: View {
    @State private var bindings = ShortcutStore.allBindings()
    @State private var errors: [ShortcutID: String] = [:]
    @State private var token = 0

    var body: some View {
        Group {
            ForEach(ShortcutGroup.allCases, id: \.self) { group in
                Section {
                    ForEach(ShortcutCatalog.ids(in: group)) { id in row(id) }
                } header: {
                    Text(LocalizedStringKey(group.rawValue))
                }
            }
            SettingsSection(
                footer: "Click a field, then press a combination that includes ⌘, ⌃ or ⌥. Esc cancels. A shortcut for a feature that is switched off in its own settings does nothing until you turn the feature on. If another app already owns a combination, macOS silently refuses it for us, so pick another one."
            ) {
                SettingsButtonRow("All shortcuts", button: "Reset All to Defaults") {
                    ShortcutStore.resetAll()
                    errors = [:]
                    bindings = ShortcutStore.allBindings()
                    token += 1
                }
            }
        }
        .id(token)
    }

    private func row(_ id: ShortcutID) -> some View {
        LabeledContent {
            HStack(spacing: 8) {
                RecorderRepresentable(shortcut: binding(for: id)).frame(width: 130, height: 24)
                Button { binding(for: id).wrappedValue = .none } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless).help("Remove shortcut").disabled(!(bindings[id]?.isSet ?? false))
                Button { reset(id) } label: {
                    Image(systemName: "arrow.counterclockwise").foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless).help("Reset to \(ShortcutCatalog.defaultBinding(id).display)")
                .disabled(bindings[id] == ShortcutCatalog.defaultBinding(id))
            }
        } label: {
            Text(ShortcutCatalog.title(id))
            if let message = errors[id] { Text(message).foregroundStyle(.orange) }
        }
    }

    private func binding(for id: ShortcutID) -> Binding<DropletShortcut> {
        Binding(
            get: { bindings[id] ?? .none },
            set: { new in commit(id, new) }
        )
    }

    private func commit(_ id: ShortcutID, _ new: DropletShortcut) {
        if let problem = ShortcutStore.set(id, to: new) {
            errors[id] = problem.message
            token += 1  // snap the recorder back to the stored value
        } else {
            errors[id] = nil
        }
        bindings = ShortcutStore.allBindings()
    }

    private func reset(_ id: ShortcutID) {
        commit(id, ShortcutCatalog.defaultBinding(id))
        token += 1
    }
}
