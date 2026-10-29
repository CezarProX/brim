// AudioControlSettingsSection.swift
// Brim
//
// Audio Control droplet: per-app volume options and preferred devices.

import SwiftUI

struct AudioControlSettingsSection: View {
  @State private var remember = AppSettings.shared.audioRememberVolumes
  @State private var showPaused = AppSettings.shared.audioShowPausedApps
  @State private var includeSystem = AppSettings.shared.audioIncludeSystemSounds
  @State private var curve = AppSettings.shared.audioVolumeCurve
  @State private var boost = AppSettings.shared.audioAllowBoost
  @State private var preferredOn = AppSettings.shared.preferredDevicesEnabled
  @State private var outputFavorites = AppSettings.shared.preferredOutputUIDs
  @State private var inputFavorites = AppSettings.shared.preferredInputUIDs
  @State private var devices: [AudioDeviceRef] = []

  var body: some View {
    Group {
      group("Per-app volume") {
        Toggle("Remember volumes", isOn: $remember)
          .onChange(of: remember) { _, value in AppSettings.shared.audioRememberVolumes = value }
        Toggle("Show paused apps", isOn: $showPaused)
          .onChange(of: showPaused) { _, value in AppSettings.shared.audioShowPausedApps = value }
        Toggle("Include system sounds", isOn: $includeSystem)
          .onChange(of: includeSystem) { _, value in AppSettings.shared.audioIncludeSystemSounds = value }
        Toggle("Allow boost up to 200%", isOn: $boost)
          .onChange(of: boost) { _, value in AppSettings.shared.audioAllowBoost = value }
        Picker("Volume curve", selection: $curve) {
            ForEach(VolumeCurve.allCases) { Text($0.title).tag($0) }
          }
        .pickerStyle(.segmented).fixedSize()
        .onChange(of: curve) { _, value in
          AppSettings.shared.audioVolumeCurve = value
          AudioControlModel.shared.curveChanged()
        }
        note("Brim taps an app's audio, silences the original and plays it back through your output with the volume applied. macOS asks for \"System Audio Recording\" the first time. It needs macOS 14.2 or newer and adds a few milliseconds of delay, so lip-sync on video can drift slightly.")
      }
      group("Preferred devices") {
        Toggle("Switch to a favorite when it connects", isOn: $preferredOn)
          .onChange(of: preferredOn) { _, value in
            AppSettings.shared.preferredDevicesEnabled = value
            if value { PreferredDeviceMonitor.shared.start() } else { PreferredDeviceMonitor.shared.stop() }
          }
        favoriteList("Outputs", devices.filter { $0.isOutput && !$0.isAggregate }, $outputFavorites) {
          AppSettings.shared.preferredOutputUIDs = $0
        }
        favoriteList("Microphones", devices.filter { $0.isInput && !$0.isAggregate }, $inputFavorites) {
          AppSettings.shared.preferredInputUIDs = $0
        }
        note("Star devices in the order you prefer them. A connecting favorite becomes the default only if you are not already on a higher-ranked one. Muting every microphone lives in Agents & Meetings.")
      }
    }
    .onAppear { devices = CoreAudioDeviceDirectory().devices() }
  }

  private func favoriteList(
    _ title: String, _ list: [AudioDeviceRef], _ favorites: Binding<[String]>, save: @escaping ([String]) -> Void
  ) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title).font(.subheadline).foregroundStyle(.secondary)
      ForEach(list) { device in
        let rank = favorites.wrappedValue.firstIndex(of: device.uid)
        Button {
          var next = favorites.wrappedValue
          if let rank { next.remove(at: rank) } else { next.append(device.uid) }
          favorites.wrappedValue = next
          save(next)
        } label: {
          HStack {
            Image(systemName: rank == nil ? "star" : "star.fill").foregroundStyle(rank == nil ? Color.secondary : Color.yellow)
            Text(device.name)
            Spacer()
            if let rank { Text("#\(rank + 1)").foregroundStyle(.secondary).monospacedDigit() }
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(!preferredOn)
      }
      if list.isEmpty { Text("No devices found").font(.footnote).foregroundStyle(.secondary) }
    }
  }

  private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
    SettingsSection(title) { content() }
  }

  private func note(_ text: String) -> some View {
    SettingsFootnote(text)
  }
}
