// DropClipSettingsSection.swift
// Brim

import SwiftUI

struct DropClipSettingsSection: View {
  @State private var enabled = AppSettings.shared.dropClipEnabled
  @State private var shortcut = AppSettings.shared.dropClipShortcut
  @State private var shown = Set(AppSettings.shared.dropClipActions)
  @State private var searchTemplate = AppSettings.shared.dropClipSearchTemplate
  @State private var fallback = AppSettings.shared.dropClipCopyFallback
  @State private var trusted = SelectionReader.isTrusted

  @ViewBuilder var body: some View {
    SettingsSection("DropClip") {
      Toggle(isOn: $enabled) {
        Text("Enable the DropClip droplet")
        Text("Select text in any app, press the shortcut, and a small bar appears next to it with quick actions. Selections are read on this Mac and never stored.")
      }
        .onChange(of: enabled) { _, value in
          AppSettings.shared.dropClipEnabled = value
          DropClipController.shared.settingsChanged()
          trusted = SelectionReader.isTrusted
        }
      if enabled {
        DropletShortcutField(title: "Shortcut", shortcut: $shortcut)
          .onChange(of: shortcut) { _, value in
            AppSettings.shared.dropClipShortcut = value
            DropClipController.shared.settingsChanged()
          }
        accessibilityRow
        Toggle("If an app hides its selection, briefly copy it (your clipboard is restored)", isOn: $fallback)
          .onChange(of: fallback) { _, value in AppSettings.shared.dropClipCopyFallback = value }
      }
    }
    if enabled {
      SettingsSection(
        "Actions on the bar",
        footer: "Translate uses Apple’s on-device Translation on macOS 15 or later. On earlier versions it opens translate.google.com in your browser when you click it."
      ) {
        ForEach(DropClipAction.builtIns) { action in
          Toggle(isOn: Binding(get: { shown.contains(action) }, set: { setShown(action, $0) })) {
            Label(action.title, systemImage: action.symbol)
          }
        }
        TextField("Search address (use {text})", text: $searchTemplate)
          .onChange(of: searchTemplate) { _, value in
            if DropClipTransforms.expand(template: value, text: "test") != nil { AppSettings.shared.dropClipSearchTemplate = value }
          }
        if DropClipTransforms.expand(template: searchTemplate, text: "test") == nil {
          Text("That isn’t a valid web address template, so the previous one stays in use.").font(.caption).foregroundStyle(.orange)
        }
      }
      DropClipCustomActionsEditor()
      DropClipRulesEditor()
    }
  }

  private var accessibilityRow: some View {
    HStack {
      Image(systemName: trusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill").foregroundStyle(trusted ? Color.green : Color.orange)
      Text(trusted ? "Accessibility access granted" : "DropClip needs Accessibility access to read the selected text")
      Spacer()
      if !trusted {
        Button("Allow…") { SelectionReader.requestTrust() }
        Button("Recheck") { trusted = SelectionReader.isTrusted }
      }
    }
    .font(.callout)
  }

  private func setShown(_ action: DropClipAction, _ on: Bool) {
    if on { shown.insert(action) } else { shown.remove(action) }
    AppSettings.shared.dropClipActions = DropClipAction.builtIns.filter(shown.contains)
  }
}
