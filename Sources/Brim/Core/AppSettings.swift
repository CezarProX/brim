// AppSettings.swift
// Brim
//
// Single source of truth for all user-configurable preferences.
// Backed by UserDefaults(standard) with typed, documented accessors.
// This is a shared contract: every feature module reads/writes preferences
// exclusively through `AppSettings.shared` — never touch UserDefaults directly
// elsewhere in the app.

import Foundation
import Carbon.HIToolbox

/// Centralized, typed access to all Brim user preferences.
///
/// Backed by `UserDefaults.standard`. All properties are computed so the
/// UserDefaults suite remains the single persisted source of truth (no
/// separate in-memory cache to fall out of sync).
final class AppSettings {

    static let shared = AppSettings()

    /// Internal so feature extensions (`AppSettings+Feature.swift`) can add typed keys.
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Keys

    private enum Key {
        static let launchAtLogin = "launchAtLogin"
        static let showInDock = "showInDock"
        static let showNotifications = "showNotifications"
        static let playSound = "playSound"
        static let closeAfterCopy = "closeAfterCopy"
        static let closeAfterSave = "closeAfterSave"
        static let notchShelfEnabled = "notchShelfEnabled"
        static let callIntegrationEnabled = "callIntegrationEnabled"
        static let enabledMusicSources = "enabledMusicSources"

        static let hotkeyKeyCode = "hotkeyKeyCode"
        static let hotkeyModifiers = "hotkeyModifiers"

        static let defaultImageFormat = "defaultImageFormat"
        static let jpgQuality = "jpgQuality"
        static let defaultSaveFolder = "defaultSaveFolder"
        static let autoSave = "autoSave"
        static let rememberLastSaveLocation = "rememberLastSaveLocation"
        static let lastSaveLocation = "lastSaveLocation"
        static let fileNamePrefix = "fileNamePrefix"
        static let includeDateInFileName = "includeDateInFileName"

        static let copyAfterSelection = "copyAfterSelection"
        static let preserveTransparency = "preserveTransparency"
        static let copyAtOriginalResolution = "copyAtOriginalResolution"

        static let autoUpload = "autoUpload"
        static let autoCopyLink = "autoCopyLink"
        static let uploadServiceURL = "uploadServiceURL"

        static let saveHistoryOfClipboardCaptures = "saveHistoryOfClipboardCaptures"
    }

    // MARK: - General

    var launchAtLogin: Bool {
        get { defaults.object(forKey: Key.launchAtLogin) as? Bool ?? false }
        set { defaults.set(newValue, forKey: Key.launchAtLogin) }
    }

    var showInDock: Bool {
        get { defaults.object(forKey: Key.showInDock) as? Bool ?? false }
        set { defaults.set(newValue, forKey: Key.showInDock) }
    }

    var showNotifications: Bool {
        get { defaults.object(forKey: Key.showNotifications) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.showNotifications) }
    }

    var playSound: Bool {
        get { defaults.object(forKey: Key.playSound) as? Bool ?? false }
        set { defaults.set(newValue, forKey: Key.playSound) }
    }

    var closeAfterCopy: Bool {
        get { defaults.object(forKey: Key.closeAfterCopy) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.closeAfterCopy) }
    }

    var closeAfterSave: Bool {
        get { defaults.object(forKey: Key.closeAfterSave) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.closeAfterSave) }
    }

    // MARK: - Hotkey

    var calendarActivityEnabled: Bool {
        get { defaults.bool(forKey: "calendarActivityEnabled") }
        set { defaults.set(newValue, forKey: "calendarActivityEnabled") }
    }

    /// Flash charging, unplugging and low-battery changes in the notch.
    var powerFlashesEnabled: Bool {
        get { defaults.object(forKey: "powerFlashesEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "powerFlashesEnabled") }
    }

    /// Flash when the camera or microphone starts or stops being used.
    var privacyFlashesEnabled: Bool {
        get { defaults.object(forKey: "privacyFlashesEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "privacyFlashesEnabled") }
    }

    /// Off by default: watching Downloads makes macOS ask for folder access.
    var downloadFlashesEnabled: Bool {
        get { defaults.bool(forKey: "downloadFlashesEnabled") }
        set { defaults.set(newValue, forKey: "downloadFlashesEnabled") }
    }

    /// Show the front browser's tab and navigation in the island.
    var browserSkinEnabled: Bool {
        get { defaults.object(forKey: "browserSkinEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "browserSkinEnabled") }
    }

    /// Show live Claude Code and Codex sessions, read from their local transcripts.
    var codingAgentSkinEnabled: Bool {
        get { defaults.object(forKey: "codingAgentSkinEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "codingAgentSkinEnabled") }
    }

    /// Widgets on the quiet Home page, in order: `name` at its default size, or `name:size`.
    var homeWidgets: [String] {
        get {
            guard let stored = defaults.stringArray(forKey: "homeWidgets") else { return ["media", "captures"] }
            guard !defaults.bool(forKey: "homeWidgetsKeepsMedia") else { return stored }
            // Media could not be removed before, so a saved list without it was never a choice:
            // give it back once. Later saves set the flag and respect a removal.
            let migrated = stored.contains { $0.hasPrefix("media") } ? stored : Array((["media"] + stored).prefix(8))
            defaults.set(migrated, forKey: "homeWidgets")
            defaults.set(true, forKey: "homeWidgetsKeepsMedia")
            return migrated
        }
        set {
            // Eight small widgets fill both pages of the Home grid (HomeWidgetGrid.maxWidgets).
            defaults.set(Array(newValue.prefix(8)), forKey: "homeWidgets")
            defaults.set(true, forKey: "homeWidgetsKeepsMedia")
        }
    }

    /// Shaking the pointer during a file drag opens a floating basket.
    var basketEnabled: Bool {
        get { defaults.object(forKey: "basketEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "basketEnabled") }
    }

    var remindersActivityEnabled: Bool {
        get { defaults.bool(forKey: "remindersActivityEnabled") }
        set { defaults.set(newValue, forKey: "remindersActivityEnabled") }
    }

    var agentStatusFile: URL? {
        get { defaults.url(forKey: "agentStatusFile") }
        set { defaults.set(newValue, forKey: "agentStatusFile") }
    }

    var workspaceActivityEnabled: Bool {
        get { defaults.bool(forKey: "workspaceActivityEnabled") }
        set { defaults.set(newValue, forKey: "workspaceActivityEnabled") }
    }

    var systemActivityEnabled: Bool {
        get { defaults.object(forKey: "systemActivityEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "systemActivityEnabled") }
    }

    /// Frosted glass beneath the island and its navigation capsule; off keeps it solid black.
    var islandGlassEnabled: Bool {
        get { defaults.object(forKey: "islandGlassEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "islandGlassEnabled") }
    }

    var notchShelfEnabled: Bool {
        get { defaults.object(forKey: Key.notchShelfEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.notchShelfEnabled) }
    }

    var callIntegrationEnabled: Bool {
        get { defaults.object(forKey: Key.callIntegrationEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.callIntegrationEnabled) }
    }

    var enabledMusicSources: [String] {
        get { defaults.stringArray(forKey: Key.enabledMusicSources) ?? [] }
        set { defaults.set(Array(Set(newValue)).sorted(), forKey: Key.enabledMusicSources) }
    }

    /// Carbon virtual key code. Default 25 == kVK_ANSI_9 ("9").
    var hotkeyKeyCode: Int {
        get { defaults.object(forKey: Key.hotkeyKeyCode) as? Int ?? 25 }
        set { defaults.set(newValue, forKey: Key.hotkeyKeyCode) }
    }

    /// Carbon event modifier flags (cmdKey | shiftKey by default), suitable
    /// for `RegisterEventHotKey`. NOT the same bit layout as `NSEvent.ModifierFlags`.
    var hotkeyModifiers: Int {
        get {
            defaults.object(forKey: Key.hotkeyModifiers) as? Int
                ?? Int(cmdKey | shiftKey)
        }
        set { defaults.set(newValue, forKey: Key.hotkeyModifiers) }
    }

    // MARK: - Save / file format

    /// Allowed values: "png", "jpg".
    var defaultImageFormat: String {
        get {
            let raw = defaults.string(forKey: Key.defaultImageFormat) ?? "png"
            return ["png", "jpg"].contains(raw) ? raw : "png"
        }
        set {
            let sanitized = ["png", "jpg"].contains(newValue) ? newValue : "png"
            defaults.set(sanitized, forKey: Key.defaultImageFormat)
        }
    }

    var jpgQuality: Double {
        get {
            let value = defaults.object(forKey: Key.jpgQuality) as? Double ?? 0.9
            return min(max(value, 0.0), 1.0)
        }
        set { defaults.set(min(max(newValue, 0.0), 1.0), forKey: Key.jpgQuality) }
    }

    var defaultSaveFolder: URL? {
        get { defaults.url(forKey: Key.defaultSaveFolder) }
        set { defaults.set(newValue, forKey: Key.defaultSaveFolder) }
    }

    var autoSave: Bool {
        get { defaults.object(forKey: Key.autoSave) as? Bool ?? false }
        set { defaults.set(newValue, forKey: Key.autoSave) }
    }

    var rememberLastSaveLocation: Bool {
        get { defaults.object(forKey: Key.rememberLastSaveLocation) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.rememberLastSaveLocation) }
    }

    var lastSaveLocation: URL? {
        get { defaults.url(forKey: Key.lastSaveLocation) }
        set { defaults.set(newValue, forKey: Key.lastSaveLocation) }
    }

    var fileNamePrefix: String {
        get { defaults.string(forKey: Key.fileNamePrefix) ?? "Screenshot" }
        set { defaults.set(newValue, forKey: Key.fileNamePrefix) }
    }

    var includeDateInFileName: Bool {
        get { defaults.object(forKey: Key.includeDateInFileName) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.includeDateInFileName) }
    }

    // MARK: - Copy behavior

    var copyAfterSelection: Bool {
        get { defaults.object(forKey: Key.copyAfterSelection) as? Bool ?? false }
        set { defaults.set(newValue, forKey: Key.copyAfterSelection) }
    }

    var preserveTransparency: Bool {
        get { defaults.object(forKey: Key.preserveTransparency) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.preserveTransparency) }
    }

    var copyAtOriginalResolution: Bool {
        get { defaults.object(forKey: Key.copyAtOriginalResolution) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.copyAtOriginalResolution) }
    }

    // MARK: - Upload

    var autoUpload: Bool {
        get { defaults.object(forKey: Key.autoUpload) as? Bool ?? false }
        set { defaults.set(newValue, forKey: Key.autoUpload) }
    }

    var autoCopyLink: Bool {
        get { defaults.object(forKey: Key.autoCopyLink) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.autoCopyLink) }
    }

    var uploadServiceURL: String {
        get { defaults.string(forKey: Key.uploadServiceURL) ?? "https://0x0.st" }
        set { defaults.set(newValue, forKey: Key.uploadServiceURL) }
    }

    /// The upload host the user agreed to send screenshots to (see `UploadConsent`).
    var uploadHostAcknowledged: String? {
        get { defaults.string(forKey: "uploadHostAcknowledged") }
        set { defaults.set(newValue, forKey: "uploadHostAcknowledged") }
    }

    // MARK: - History

    var saveHistoryOfClipboardCaptures: Bool {
        get { defaults.object(forKey: Key.saveHistoryOfClipboardCaptures) as? Bool ?? false }
        set { defaults.set(newValue, forKey: Key.saveHistoryOfClipboardCaptures) }
    }

    // MARK: - Helpers

    /// Builds a default file name (without extension) from the current
    /// `fileNamePrefix` / `includeDateInFileName` settings, e.g.
    /// "Screenshot 2026-07-21 at 00.35.12".
    static func defaultFileName(date: Date = Date()) -> String {
        let prefix = sanitizedFileNamePrefix(AppSettings.shared.fileNamePrefix)
        guard AppSettings.shared.includeDateInFileName else {
            return prefix
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "\(prefix) \(formatter.string(from: date))"
    }

    /// Sanitizes a user-supplied file name prefix so it can never escape the
    /// destination folder (path traversal) or otherwise produce an invalid
    /// path component: strips path separators ("/", ":"), null characters,
    /// and collapses ".." sequences, then trims whitespace. Falls back to
    /// "Screenshot" if the result would be empty.
    private static func sanitizedFileNamePrefix(_ raw: String) -> String {
        var sanitized = raw
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\0", with: "")

        while sanitized.contains("..") {
            sanitized = sanitized.replacingOccurrences(of: "..", with: ".")
        }

        sanitized = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)

        return sanitized.isEmpty ? "Screenshot" : sanitized
    }
}
