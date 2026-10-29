// TrayExtrasSettingsSection.swift
// Brim
//
// Where trays appear, how originals are protected, tracked folders, the Mail app and the optional
// command-line tools Transform can use. Embedded in TransformSettingsSection.

import AppKit
import SwiftUI

struct TrayExtrasSettingsSection: View {
  @State private var placement = AppSettings.shared.trayPlacement
  @State private var openAfterDrop = AppSettings.shared.trayOpenAfterDrop
  @State private var protect = AppSettings.shared.trayProtectOriginals
  @State private var removeAfterDragOut = AppSettings.shared.trayRemoveAfterDragOut
  @State private var sync = AppSettings.shared.floatingTraySync
  @State private var tracked = AppSettings.shared.trackedFoldersEnabled
  @State private var folders = AppSettings.shared.trackedFolderPaths
  @State private var autoOCR = AppSettings.shared.trackedFoldersAutoOCR
  @State private var mailApp = AppSettings.shared.trayMailAppBundleID
  @State private var mailApps = MailAppChoice.installed()
  @State private var toolTick = 0

  var body: some View {
    Group {
      behavior
      trackedFolders
      mail
      optionalTools
    }
  }

  private var behavior: some View {
    section("Tray behavior") {
      Picker("Where the tray appears", selection: $placement) {
        ForEach(TrayPlacement.allCases) { Text($0.rawValue).tag($0) }
      }
      .onChange(of: placement) { _, value in AppSettings.shared.trayPlacement = value }
      Text(placementCaption).font(.footnote).foregroundStyle(.secondary)
      Toggle("Open the tray after a drop on the notch", isOn: $openAfterDrop)
        .onChange(of: openAfterDrop) { _, value in AppSettings.shared.trayOpenAfterDrop = value }
      Toggle("Protect originals", isOn: $protect)
        .onChange(of: protect) { _, value in AppSettings.shared.trayProtectOriginals = value }
      Text("Move to and Rename work on copies, dragging a file out hands over a copy, and Transform never trashes originals.")
        .font(.footnote).foregroundStyle(.secondary)
      Toggle("Remove items from the tray after dragging them out", isOn: $removeAfterDragOut)
        .onChange(of: removeAfterDragOut) { _, value in AppSettings.shared.trayRemoveAfterDragOut = value }
      Toggle("Keep floating trays in sync", isOn: $sync)
        .onChange(of: sync) { _, value in AppSettings.shared.floatingTraySync = value }
    }
  }

  private var placementCaption: String {
    switch placement {
    case .notch: "Drops land in the notch tray. Shaking a drag shows the quick action tiles only."
    case .floating: "Drops on the notch go to a floating tray, and shaking a drag opens one."
    case .both: "Drops on the notch fill the notch tray, and shaking a drag opens a floating tray."
    }
  }

  private var trackedFolders: some View {
    section("Tracked folders") {
      Toggle("Add new files from these folders to the tray", isOn: $tracked)
        .onChange(of: tracked) { _, value in
          AppSettings.shared.trackedFoldersEnabled = value
          TrackedFolders.shared.refresh()
        }
      ForEach(folders, id: \.self) { path in
        HStack {
          Label(FileManager.default.displayName(atPath: path), systemImage: "folder").lineLimit(1)
          Spacer()
          Button(role: .destructive) { removeFolder(path) } label: { Image(systemName: "minus.circle") }
            .buttonStyle(.borderless).help("Stop tracking this folder")
        }
      }
      Button("Add Folder…", action: addFolder)
      Toggle("Copy the text of new images (on-device OCR)", isOn: $autoOCR)
        .onChange(of: autoOCR) { _, value in AppSettings.shared.trackedFoldersAutoOCR = value }
        .disabled(!tracked)
      Text("Files already in a folder are left alone. Partial downloads are skipped until they finish.")
        .font(.footnote).foregroundStyle(.secondary)
    }
  }

  private var mail: some View {
    section("Mail action") {
      Picker("Mail app", selection: $mailApp) {
        Text("Default (Apple Mail sharing)").tag("")
        ForEach(mailApps) { Text($0.name).tag($0.bundleID) }
      }
      .onChange(of: mailApp) { _, value in AppSettings.shared.trayMailAppBundleID = value }
      Text("Apple Mail attaches the files. Other apps get the files through Open With, so attaching depends on the app.")
        .font(.footnote).foregroundStyle(.secondary)
    }
  }

  private var optionalTools: some View {
    let _ = toolTick
    return section("Optional tools") {
      ForEach(OptionalTool.allCases) { tool in
        let found = OptionalTools.url(for: tool)
        Label {
          VStack(alignment: .leading, spacing: 1) {
            Text(tool.title)
            Text(found.map { "Found at \($0.path) — unlocks \(tool.unlocks)" }
              ?? "Not installed — would unlock \(tool.unlocks) (brew install \(tool.brewFormula))")
              .font(.footnote).foregroundStyle(.secondary)
          }
        } icon: {
          Image(systemName: found == nil ? "circle.dashed" : "checkmark.circle.fill")
            .foregroundStyle(found == nil ? Color.secondary : Color.green)
        }
      }
      Button("Check Again") {
        OptionalTools.invalidate()
        toolTick += 1
      }
      Text("Brim only uses tools you already installed; it never installs anything. Archives such as 7z and RAR unpack with macOS’s built-in bsdtar.")
        .font(.footnote).foregroundStyle(.secondary)
    }
  }

  // MARK: Helpers

  private func addFolder() {
    guard let folder = FileTrayActions.chooseFolder(prompt: "Track") else { return }
    folders = Array(NSOrderedSet(array: folders + [folder.path])) as? [String] ?? folders
    AppSettings.shared.trackedFolderPaths = folders
    TrackedFolders.shared.refresh()
  }

  private func removeFolder(_ path: String) {
    folders.removeAll { $0 == path }
    AppSettings.shared.trackedFolderPaths = folders
    TrackedFolders.shared.refresh()
  }

  private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
    SettingsSection(title) { content() }
  }
}
