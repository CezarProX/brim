// BluetoothDevicesSettingsSection.swift
// Brim

import SwiftUI

/// Per-accessory switches for the Bluetooth HUDs. Lists every accessory Brim has seen so far.
struct BluetoothDevicesSettingsSection: View {
  @State private var known = AppSettings.shared.bluetoothKnownDevices
  @State private var mutedConnect = AppSettings.shared.bluetoothMutedConnect
  @State private var mutedLow = AppSettings.shared.bluetoothMutedLowBattery

  private var sorted: [(id: String, name: String)] {
    known.map { (id: $0.key, name: $0.value) }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
  }

  var body: some View {
    SettingsSection("Bluetooth devices") {
      if sorted.isEmpty {
        Text("No accessories seen yet. Turn on “Bluetooth devices connect or run low” above; devices that report a battery level show up here once they connect.")
          .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      } else {
        ForEach(sorted, id: \.id) { device in
          HStack(spacing: 10) {
            Image(systemName: "headphones").foregroundStyle(.blue).frame(width: 20)
            Text(device.name).lineLimit(1)
            Spacer()
            Toggle("Connect", isOn: flag(device.id, in: $mutedConnect, key: \.bluetoothMutedConnect))
            Toggle("Low battery", isOn: flag(device.id, in: $mutedLow, key: \.bluetoothMutedLowBattery))
          }
          .toggleStyle(.checkbox)
        }
        Button("Clear the list (connected devices reappear)") { forget() }
        Text("Only accessories that report a battery level are seen; macOS shows no other Bluetooth devices without a Bluetooth permission prompt, which Brim avoids.")
          .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      }
    }
    .onAppear { known = AppSettings.shared.bluetoothKnownDevices }
  }

  /// A checkbox that is ON unless the id is in the muted set.
  private func flag(
    _ id: String, in muted: Binding<Set<String>>, key: ReferenceWritableKeyPath<AppSettings, Set<String>>
  ) -> Binding<Bool> {
    Binding(
      get: { !muted.wrappedValue.contains(id) },
      set: { on in
        var next = muted.wrappedValue
        if on { next.remove(id) } else { next.insert(id) }
        muted.wrappedValue = next
        AppSettings.shared[keyPath: key] = next
      })
  }

  private func forget() {
    AppSettings.shared.bluetoothKnownDevices = [:]
    known = [:]
  }
}
