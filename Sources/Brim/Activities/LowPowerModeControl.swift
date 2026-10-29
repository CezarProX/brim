// LowPowerModeControl.swift
// Brim
//
// Low Power Mode has no public API to change. `pmset -a lowpowermode` works but needs an administrator,
// so the button runs the documented /usr/bin/pmset through the standard macOS authorization prompt.
// If that fails for any reason other than the user cancelling, the Battery settings pane opens instead.
// Brim never stores the password and never runs anything privileged without that prompt.

import AppKit
import Foundation

enum LowPowerModeControl {
  /// AppleScript `do shell script` source for setting Low Power Mode.
  static func script(enable: Bool) -> String {
    "do shell script \"/usr/bin/pmset -a lowpowermode \(enable ? 1 : 0)\" with administrator privileges"
  }

  static let batterySettingsURL = URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension")!

  enum Result: Equatable {
    case changed
    case cancelled
    case failed(code: Int)
  }

  /// AppleScript error -128 means the user dismissed the password prompt.
  static func classify(errorNumber: Int?) -> Result {
    switch errorNumber {
    case nil: return .changed
    case -128: return .cancelled
    case let code?: return .failed(code: code)
    }
  }

  @MainActor
  static func set(enabled: Bool) -> Result {
    var info: NSDictionary?
    NSAppleScript(source: script(enable: enabled))?.executeAndReturnError(&info)
    let result = classify(errorNumber: info?[NSAppleScript.errorNumber] as? Int)
    if case .failed = result { NSWorkspace.shared.open(batterySettingsURL) }
    return result
  }
}
