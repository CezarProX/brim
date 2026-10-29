// BluetoothDevicePrefs.swift
// Brim
//
// Per-device switches for the Bluetooth HUDs: which accessories may flash a connect / disconnect
// card and which may raise a low-battery alert. Pure so it can be tested.

import Foundation

struct BluetoothDevicePrefs: Equatable {
  var mutedConnect: Set<String> = []
  var mutedLowBattery: Set<String> = []

  /// Drops events for devices the user switched off. `ids` maps a device name to its id; an event
  /// whose device can't be resolved is kept (better a HUD too many than a silent miss).
  func filter(_ events: [BluetoothHUDRules.Event], ids: [String: String]) -> [BluetoothHUDRules.Event] {
    events.filter { event in
      switch event {
      case .connected(let name, _), .disconnected(let name):
        return ids[name].map { !mutedConnect.contains($0) } ?? true
      case .lowBattery(let name, _):
        return ids[name].map { !mutedLowBattery.contains($0) } ?? true
      }
    }
  }

  /// Adds new devices to the remembered list without renaming ones already known.
  static func remember(
    _ known: [String: String], devices: [BluetoothHUDRules.Device]
  ) -> [String: String] {
    var next = known
    for device in devices where next[device.id] == nil || next[device.id] != device.name {
      next[device.id] = device.name
    }
    return next
  }
}
