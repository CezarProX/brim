// AppSettings+Recording.swift
// Brim
//
// Preferences for the screen recorder and the Studio editor.

import Carbon.HIToolbox
import Foundation

extension AppSettings {
    /// Default ⌃⇧5, echoing macOS' own recorder (⌘⇧5, reserved). ⌘⇧6 is the system Touch Bar shot.
    static let defaultRecordScreenShortcut = DropletShortcut(keyCode: kVK_ANSI_5, modifiers: Int(controlKey | shiftKey))

    var recordScreenShortcut: DropletShortcut {
        get { .load("recordScreen", fallback: Self.defaultRecordScreenShortcut, from: defaults) }
        set { newValue.save("recordScreen", to: defaults) }
    }

    /// 30 or 60.
    var recordingFPS: Int {
        get { defaults.object(forKey: "recordingFPS") as? Int == 30 ? 30 : 60 }
        set { defaults.set(newValue == 30 ? 30 : 60, forKey: "recordingFPS") }
    }

    var recordingMicrophone: Bool {
        get { defaults.bool(forKey: "recordingMicrophone") }
        set { defaults.set(newValue, forKey: "recordingMicrophone") }
    }

    var recordingSystemAudio: Bool {
        get { defaults.bool(forKey: "recordingSystemAudio") }
        set { defaults.set(newValue, forKey: "recordingSystemAudio") }
    }

    /// Record at the display's native pixel density instead of 1×.
    var recordingRetina: Bool {
        get { defaults.object(forKey: "recordingRetina") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "recordingRetina") }
    }

    /// Seconds of 3-2-1 before recording; 0 turns the countdown off.
    var recordingCountdown: Int {
        get { min(max(defaults.object(forKey: "recordingCountdown") as? Int ?? 3, 0), 10) }
        set { defaults.set(min(max(newValue, 0), 10), forKey: "recordingCountdown") }
    }

    /// "display", "window" or "area".
    var recordingSourceKind: String {
        get { defaults.string(forKey: "recordingSourceKind") ?? "display" }
        set { defaults.set(newValue, forKey: "recordingSourceKind") }
    }

    var studioExportSettings: ExportSettings {
        get { defaults.data(forKey: "studioExportSettings").flatMap { try? JSONDecoder().decode(ExportSettings.self, from: $0) } ?? ExportSettings() }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: "studioExportSettings") }
    }

    var studioPresets: [StudioStylePreset] {
        get { defaults.data(forKey: "studioPresets").flatMap { try? JSONDecoder().decode([StudioStylePreset].self, from: $0) } ?? [] }
        set { defaults.set(try? JSONEncoder().encode(Array(newValue.prefix(24))), forKey: "studioPresets") }
    }

    /// The look new recordings start with.
    var studioDefaultStyle: RecordingStyle {
        get { defaults.data(forKey: "studioDefaultStyle").flatMap { try? JSONDecoder().decode(RecordingStyle.self, from: $0) } ?? .standard }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: "studioDefaultStyle") }
    }
}
