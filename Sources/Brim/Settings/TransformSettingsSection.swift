// TransformSettingsSection.swift
// Brim
//
// Settings for Transform, Quick Actions, the notch file tray and the floating trays.

import SwiftUI

struct TransformSettingsSection: View {
  @State private var destination = AppSettings.shared.transformDestination
  @State private var reveal = AppSettings.shared.transformRevealInFinder
  @State private var trash = AppSettings.shared.transformTrashOriginals
  @State private var keepInTray = AppSettings.shared.transformKeepResultsInTray
  @State private var imageQuality = AppSettings.shared.transformImageQuality
  @State private var imageFormat = AppSettings.shared.transformImageFormat
  @State private var videoQuality = AppSettings.shared.transformVideoQuality
  @State private var pdfQuality = AppSettings.shared.transformPDFQuality
  @State private var presets = AppSettings.shared.transformUserPresets
  @State private var extras = AppSettings.shared.quickActionExtras
  @State private var retention = AppSettings.shared.trayRetention
  @State private var multiple = AppSettings.shared.floatingTrayMultiple
  @State private var switcher = AppSettings.shared.floatingTraySwitcher
  @State private var autoHide = AppSettings.shared.floatingTrayAutoHideSeconds
  @State private var sensitivity = Double(AppSettings.shared.shakeSensitivity)

  /// The tray and Basket first; conversions and the rest are advanced.
  enum Part { case basic, advanced }
  var part: Part?

  var body: some View {
    Group {
      if part != .advanced { fileTray }
      if part != .basic {
        results
        defaults
        presetsList
        quickActions
        TrayExtrasSettingsSection()
      }
    }
  }

  // MARK: Sections

  private var results: some View {
    section("Transform results") {
      Picker("Save results", selection: $destination) {
        ForEach(TransformDestination.allCases) { Text($0.rawValue).tag($0) }
      }
      .onChange(of: destination) { _, value in AppSettings.shared.transformDestination = value }
      Toggle("Show results in Finder when done", isOn: $reveal)
        .onChange(of: reveal) { _, value in AppSettings.shared.transformRevealInFinder = value }
      Toggle("Keep results on the Shelf", isOn: $keepInTray)
        .onChange(of: keepInTray) { _, value in AppSettings.shared.transformKeepResultsInTray = value }
      Toggle("Move originals to the Trash after a successful transform", isOn: $trash)
        .onChange(of: trash) { _, value in AppSettings.shared.transformTrashOriginals = value }
      Text("Originals are always protected: results get new names like “photo-compressed.jpg” and never overwrite a file. Everything runs on this Mac.")
        .font(.footnote).foregroundStyle(.secondary)
    }
  }

  private var defaults: some View {
    section("Defaults") {
      LabeledContent("Image quality") {
        HStack {
          Slider(value: $imageQuality, in: 0.1...1).frame(maxWidth: 240)
            .onChange(of: imageQuality) { _, value in AppSettings.shared.transformImageQuality = value }
          Text("\(Int(imageQuality * 100))%").monospacedDigit().foregroundStyle(.secondary).frame(width: 40, alignment: .trailing)
        }
      }
      Picker("Compressed images", selection: $imageFormat) {
        ForEach(TransformImageFormat.writable().filter { $0 != .tiff }) { Text($0.rawValue).tag($0) }
      }
      .onChange(of: imageFormat) { _, value in AppSettings.shared.transformImageFormat = value }
      Picker("Video quality", selection: $videoQuality) {
        ForEach(TransformQuality.allCases) { Text($0.rawValue).tag($0) }
      }
      .onChange(of: videoQuality) { _, value in AppSettings.shared.transformVideoQuality = value }
      Picker("PDF quality", selection: $pdfQuality) {
        ForEach(TransformQuality.allCases) { Text($0.rawValue).tag($0) }
      }
      .onChange(of: pdfQuality) { _, value in AppSettings.shared.transformPDFQuality = value }
    }
  }

  private var presetsList: some View {
    section("Presets") {
      ForEach(TransformPreset.builtIn) { preset in
        Label(preset.name, systemImage: preset.symbol).foregroundStyle(.secondary)
      }
      ForEach(presets) { preset in
        HStack {
          Label(preset.name, systemImage: preset.symbol)
          Spacer()
          Button(role: .destructive) {
            presets.removeAll { $0.id == preset.id }
            AppSettings.shared.transformUserPresets = presets
          } label: { Image(systemName: "trash") }
          .buttonStyle(.borderless)
        }
      }
      Text("Save your own from the Presets menu in the Transform panel.").font(.footnote).foregroundStyle(.secondary)
    }
  }

  private var quickActions: some View {
    section("Quick Actions") {
      Text("Tiles that appear when you drag files onto the notch, the island or a floating tray. Drop and Transform are always there.")
        .font(.footnote).foregroundStyle(.secondary)
      ForEach(0..<AppSettings.maximumQuickActionExtras, id: \.self) { slot in
        Picker("Tile \(slot + 3)", selection: binding(forSlot: slot)) {
          Text("None").tag(DropTarget?.none)
          ForEach(DropTarget.optional) { Text($0.title).tag(DropTarget?.some($0)) }
        }
      }
    }
  }

  private var fileTray: some View {
    section("File tray") {
      Picker("Keep files on the Shelf", selection: $retention) {
        ForEach(FileTrayRetention.allCases) { Text($0.rawValue).tag($0) }
      }
      .onChange(of: retention) { _, value in
        AppSettings.shared.trayRetention = value
        FileTrayStore.shared.pruneExpired()
      }
      Text("The Shelf holds references, not copies. Older ones are forgotten; the files themselves are never deleted.")
        .font(.footnote).foregroundStyle(.secondary)
      Toggle("Open a new floating tray on each shake (up to \(AppSettings.maximumFloatingTrays))", isOn: $multiple)
        .onChange(of: multiple) { _, value in AppSettings.shared.floatingTrayMultiple = value }
      Toggle("Show the tray switcher when several are open", isOn: $switcher)
        .onChange(of: switcher) { _, value in AppSettings.shared.floatingTraySwitcher = value }
      Picker("Hide empty trays", selection: $autoHide) {
        Text("Never").tag(0)
        ForEach([3, 5, 10, 30], id: \.self) { Text("After \($0) seconds").tag($0) }
      }
      .onChange(of: autoHide) { _, value in
        AppSettings.shared.floatingTrayAutoHideSeconds = value
        FloatingBasketController.shared.settingsChanged()
      }
      LabeledContent("Shake sensitivity") {
        HStack {
          Slider(value: $sensitivity, in: 1...5, step: 1).frame(maxWidth: 220)
            .onChange(of: sensitivity) { _, value in
              AppSettings.shared.shakeSensitivity = Int(value)
              FloatingBasketController.shared.settingsChanged()
            }
          Text(["Low", "Gentle", "Balanced", "High", "Max"][Int(sensitivity) - 1])
            .foregroundStyle(.secondary).frame(width: 64, alignment: .trailing)
        }
      }
    }
  }

  // MARK: Helpers

  private func binding(forSlot slot: Int) -> Binding<DropTarget?> {
    Binding(
      get: { extras.indices.contains(slot) ? extras[slot] : nil },
      set: { newValue in
        var next = extras
        while next.count <= slot { next.append(.airDrop) }
        if let newValue { next[slot] = newValue } else { next.remove(at: slot) }
        extras = DropTarget.sanitizedExtras(next)
        AppSettings.shared.quickActionExtras = extras
      })
  }

  private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
    SettingsSection(title) { content() }
  }
}
