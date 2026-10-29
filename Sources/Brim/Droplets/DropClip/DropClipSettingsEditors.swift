// DropClipSettingsEditors.swift
// Brim
//
// Custom-action and per-app-rule editors used by the DropClip settings section.

import AppKit
import SwiftUI

struct DropClipCustomActionsEditor: View {
  @State private var actions = AppSettings.shared.dropClipCustomActions

  var body: some View {
    SettingsSection("Custom actions") {
      ForEach($actions) { $action in
        VStack(alignment: .leading, spacing: 4) {
          HStack {
            TextField("Name", text: $action.title).textFieldStyle(.roundedBorder).frame(maxWidth: 160)
            Picker("", selection: $action.kind) {
              Text("Open URL").tag(DropClipCustomAction.Kind.url)
              Text("Shell snippet").tag(DropClipCustomAction.Kind.shell)
            }.labelsHidden().frame(width: 130)
            Spacer()
            Button(role: .destructive) { actions.removeAll { $0.id == action.id } } label: { Image(systemName: "trash") }
              .buttonStyle(.borderless)
          }
          TextField(action.kind == .url ? "https://example.com/?q={text}" : "tr a-z A-Z   (text arrives on stdin)", text: $action.template)
            .textFieldStyle(.roundedBorder).font(.system(.caption, design: .monospaced))
          if action.kind == .url, DropClipTransforms.expand(template: action.template, text: "sample text") == nil {
            Text("Use {text} (or {text+} for + spaces) in a web address.").font(.caption).foregroundStyle(.orange)
          }
          if action.kind == .shell {
            Text("Asks for confirmation every time. Your text is in $DROPCLIP_TEXT and on standard input, never pasted into the command.")
              .font(.footnote).foregroundStyle(.secondary)
          }
        }
        .padding(.vertical, 2)
      }
      Button { actions.append(DropClipCustomAction(title: "New action", kind: .url, template: "https://")) } label: {
        Label("Add custom action", systemImage: "plus")
      }
      .disabled(actions.count >= 12)
    }
    .onChange(of: actions) { _, value in AppSettings.shared.dropClipCustomActions = value }
  }
}

struct DropClipRulesEditor: View {
  @State private var rules = AppSettings.shared.dropClipRules

  var body: some View {
    SettingsSection("Per-app rules", footer: "Hide the bar in an app, or remove actions you don’t want there.") {
      ForEach(rules.apps.keys.sorted(), id: \.self) { bundleID in row(bundleID) }
      Menu {
        ForEach(runningApps, id: \.bundleIdentifier) { app in
          Button(app.localizedName ?? app.bundleIdentifier ?? "App") {
            if let id = app.bundleIdentifier { rules = rules.setting(rules.apps[id] ?? DropClipAppRule(), for: id) }
          }
        }
      } label: { Label("Add an app", systemImage: "plus") }
    }
    .onChange(of: rules) { _, value in AppSettings.shared.dropClipRules = value }
  }

  private var runningApps: [NSRunningApplication] {
    NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil }
      .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
  }

  private func row(_ bundleID: String) -> some View {
    let rule = rules.apps[bundleID] ?? DropClipAppRule()
    let name = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID).map { FileManager.default.displayName(atPath: $0.path) } ?? bundleID
    return HStack {
      Toggle(name, isOn: Binding(get: { rule.enabled }, set: { rules = rules.setting(DropClipAppRule(enabled: $0, hidden: rule.hidden), for: bundleID) }))
      Spacer()
      Menu("Actions") {
        ForEach(DropClipAction.builtIns) { action in
          Toggle(action.title, isOn: Binding(
            get: { !rule.hidden.contains(action.rawValue) },
            set: { shown in
              var hidden = rule.hidden
              if shown { hidden.remove(action.rawValue) } else { hidden.insert(action.rawValue) }
              rules = rules.setting(DropClipAppRule(enabled: rule.enabled, hidden: hidden), for: bundleID)
            }))
        }
      }
      .menuStyle(.borderlessButton).frame(width: 80).disabled(!rule.enabled)
      Button { rules = rules.removing(bundleID) } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.borderless)
    }
  }
}
