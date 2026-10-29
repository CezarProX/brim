// AppSettings+Bluetooth.swift
// Brim

import Foundation

extension AppSettings {
  /// Bluetooth accessories seen so far (id -> name), so the settings list can show devices that are
  /// not connected right now.
  var bluetoothKnownDevices: [String: String] {
    get { defaults.dictionary(forKey: "hudBluetoothKnown") as? [String: String] ?? [:] }
    set { defaults.set(newValue, forKey: "hudBluetoothKnown") }
  }

  /// Device ids whose connect / disconnect HUD is switched off.
  var bluetoothMutedConnect: Set<String> {
    get { Set(defaults.stringArray(forKey: "hudBluetoothMutedConnect") ?? []) }
    set { defaults.set(Array(newValue).sorted(), forKey: "hudBluetoothMutedConnect") }
  }

  /// Device ids whose low-battery alert is switched off.
  var bluetoothMutedLowBattery: Set<String> {
    get { Set(defaults.stringArray(forKey: "hudBluetoothMutedLow") ?? []) }
    set { defaults.set(Array(newValue).sorted(), forKey: "hudBluetoothMutedLow") }
  }
}
