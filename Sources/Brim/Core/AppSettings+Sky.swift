// AppSettings+Sky.swift
// Brim

import Foundation

extension AppSettings {
  /// Lock-screen chip with the next sunrise or sunset. Opt-in: contacts open-meteo.com.
  var lockSunChipEnabled: Bool {
    get { defaults.object(forKey: "lockSunChipEnabled") as? Bool ?? false }
    set { defaults.set(newValue, forKey: "lockSunChipEnabled") }
  }

  /// Lock-screen chip with the local air quality index. Opt-in: contacts open-meteo.com.
  var lockAirQualityChipEnabled: Bool {
    get { defaults.object(forKey: "lockAirQualityChipEnabled") as? Bool ?? false }
    set { defaults.set(newValue, forKey: "lockAirQualityChipEnabled") }
  }
}
