// AppSettings+LockHUDv2.swift
// Brim
//
// Wave-5 preferences: lock screen v2 (artwork scene, lyrics, edge sliders, keep-awake, status items),
// download progress, HUD display target, capture thumbnail and "notify me".

import Foundation

/// Which displays show the compact HUDs.
enum HUDDisplayTarget: String, CaseIterable, Identifiable {
    case underPointer, mainDisplay, allDisplays
    var id: String { rawValue }
    var title: String {
        switch self {
        case .underPointer: "Under pointer"
        case .mainDisplay: "Main display"
        case .allDisplays: "All displays"
        }
    }
}

extension AppSettings {
    private func v2Flag(_ key: String, _ value: Bool) -> Bool { defaults.object(forKey: key) as? Bool ?? value }

    // MARK: Lock screen v2

    /// Tapping the artwork on the lock screen opens the fullscreen artwork scene.
    var lockScreenArtworkScene: Bool {
        get { v2Flag("lockScreenArtworkScene", true) }
        set { defaults.set(newValue, forKey: "lockScreenArtworkScene") }
    }
    /// Synced lyrics above the Now Playing card. Uses LRCLIB over HTTPS (the existing lyrics setting
    /// for the island must also be on, because it is what fetches them).
    var lockScreenLyrics: Bool {
        get { v2Flag("lockScreenLyrics", true) }
        set { defaults.set(newValue, forKey: "lockScreenLyrics") }
    }
    var lockScreenEdgeSliders: Bool {
        get { v2Flag("lockScreenEdgeSliders", true) }
        set { defaults.set(newValue, forKey: "lockScreenEdgeSliders") }
    }
    /// Edge sliders on the desktop replace the notch HUD for volume and brightness. Off by default.
    var desktopEdgeSliders: Bool {
        get { v2Flag("desktopEdgeSliders", false) }
        set { defaults.set(newValue, forKey: "desktopEdgeSliders") }
    }
    /// Minutes to keep the display awake after locking. 0 = off.
    var lockScreenKeepAwakeMinutes: Int {
        get { min(120, max(0, defaults.object(forKey: "lockScreenKeepAwakeMinutes") as? Int ?? 0)) }
        set { defaults.set(min(120, max(0, newValue)), forKey: "lockScreenKeepAwakeMinutes") }
    }
    /// Status-row tile ids the user switched off ("battery", "calendar", "weather", ...).
    var lockScreenHiddenStatusItems: Set<String> {
        get { Set(defaults.stringArray(forKey: "lockScreenHiddenStatusItems") ?? []) }
        set { defaults.set(newValue.sorted(), forKey: "lockScreenHiddenStatusItems") }
    }

    // MARK: Downloads, recordings, notifications

    /// Progress ring and time left in the compact island (needs `downloadFlashesEnabled`, which owns the
    /// Downloads-folder access prompt).
    var downloadProgressRing: Bool {
        get { v2Flag("downloadProgressRing", true) }
        set { defaults.set(newValue, forKey: "downloadProgressRing") }
    }
    /// Move a .dmg to the Trash after its volume was ejected (install finished).
    var trashDiskImageAfterInstall: Bool {
        get { v2Flag("trashDiskImageAfterInstall", false) }
        set { defaults.set(newValue, forKey: "trashDiskImageAfterInstall") }
    }
    var recordingResultCard: Bool {
        get { v2Flag("recordingResultCard", true) }
        set { defaults.set(newValue, forKey: "recordingResultCard") }
    }
    /// Send a system notification when a long download, recording or transform finishes.
    var notifyLongTasks: Bool {
        get { v2Flag("notifyLongTasks", false) }
        set { defaults.set(newValue, forKey: "notifyLongTasks") }
    }
    var hudAirPodsCard: Bool {
        get { v2Flag("hudAirPodsCard", true) }
        set { defaults.set(newValue, forKey: "hudAirPodsCard") }
    }
    var hudDisplayTarget: HUDDisplayTarget {
        get { HUDDisplayTarget(rawValue: defaults.string(forKey: "hudDisplayTarget") ?? "") ?? .underPointer }
        set { defaults.set(newValue.rawValue, forKey: "hudDisplayTarget") }
    }
}
