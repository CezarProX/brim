// AppSettings+Clipboard.swift
// Brim
//
// Typed preferences for the clipboard history (smart pinboards, privacy, retention,
// auto-clear, paste-on-select, global shortcut). All keys are namespaced "clipboard.".

import Foundation

/// How long unpinned history entries are kept.
enum ClipboardKeepFor: String, CaseIterable, Identifiable, Sendable {
    case day, week, month, forever
    var id: String { rawValue }
    var title: String {
        switch self {
        case .day: return "1 day"
        case .week: return "1 week"
        case .month: return "1 month"
        case .forever: return "Forever"
        }
    }
    /// Maximum age in seconds, or nil to keep forever.
    var maxAge: TimeInterval? {
        switch self {
        case .day: return 86_400
        case .week: return 7 * 86_400
        case .month: return 30 * 86_400
        case .forever: return nil
        }
    }
}

/// Where pinned (favorite) entries sit in the library strip.
enum ClipboardPinnedPlacement: String, CaseIterable, Identifiable, Sendable {
    case beforeRecent, dateOrder
    var id: String { rawValue }
    var title: String { self == .beforeRecent ? "Before recent items" : "In date order" }
}

extension AppSettings {
    private enum ClipboardKey {
        static let pinboards = "clipboard.pinboards"
        static let skipPasswords = "clipboard.skipPasswords"
        static let cleanLinksOnCopy = "clipboard.cleanLinksOnCopy"
        static let cleanLinksOnCapture = "clipboard.cleanLinksOnCapture"
        static let clearOnQuit = "clipboard.clearOnQuit"
        static let excludedApps = "clipboard.excludedApps"
        static let historyLimit = "clipboard.historyLimit"
        static let keepFor = "clipboard.keepFor"
        static let rejectDuplicates = "clipboard.rejectDuplicates"
        static let pinnedPlacement = "clipboard.pinnedPlacement"
        static let autoClearSeconds = "clipboard.autoClearSeconds"
        static let autoClearOnlySensitive = "clipboard.autoClearOnlySensitive"
        static let pasteOnSelect = "clipboard.pasteOnSelect"
        static let copyAndFavorite = "clipboard.copyAndFavorite"
        static let shortcutEnabled = "clipboard.shortcutEnabled"
        static let autoFocusSearch = "clipboard.autoFocusSearch"
    }

    static let clipboardHistoryLimitRange = 10...500
    static let clipboardAutoClearChoices: [Int] = [0, 30, 60, 300]

    /// Raw values of the enabled smart pinboards (`ClipboardPinboard.rawValue`). Default: Code and Emails,
    /// the two the plain filter row has no equivalent for.
    var clipboardPinboards: [String] {
        get { defaults.stringArray(forKey: ClipboardKey.pinboards) ?? ["code", "emails"] }
        set { defaults.set(newValue, forKey: ClipboardKey.pinboards) }
    }

    /// Ignore items marked concealed/transient/auto-generated and copies from password managers.
    var clipboardSkipPasswords: Bool {
        get { defaults.object(forKey: ClipboardKey.skipPasswords) as? Bool ?? true }
        set { defaults.set(newValue, forKey: ClipboardKey.skipPasswords) }
    }

    /// Strip tracking parameters when a link is copied back out of history.
    var clipboardCleanLinksOnCopy: Bool {
        get { defaults.object(forKey: ClipboardKey.cleanLinksOnCopy) as? Bool ?? true }
        set { defaults.set(newValue, forKey: ClipboardKey.cleanLinksOnCopy) }
    }

    /// Strip tracking parameters from links as they are captured.
    var clipboardCleanLinksOnCapture: Bool {
        get { defaults.object(forKey: ClipboardKey.cleanLinksOnCapture) as? Bool ?? false }
        set { defaults.set(newValue, forKey: ClipboardKey.cleanLinksOnCapture) }
    }

    /// Remove unpinned history when Brim quits.
    var clipboardClearOnQuit: Bool {
        get { defaults.object(forKey: ClipboardKey.clearOnQuit) as? Bool ?? false }
        set { defaults.set(newValue, forKey: ClipboardKey.clearOnQuit) }
    }

    /// Bundle identifiers whose copies are never recorded.
    var clipboardExcludedApps: [String] {
        get { defaults.stringArray(forKey: ClipboardKey.excludedApps) ?? [] }
        set { defaults.set(newValue, forKey: ClipboardKey.excludedApps) }
    }

    /// Entry limit (10...500). 0 means no limit beyond the history's 100 MB size cap.
    var clipboardHistoryLimit: Int {
        get {
            guard let value = defaults.object(forKey: ClipboardKey.historyLimit) as? Int else { return 100 }
            return value <= 0 ? 0 : min(max(value, Self.clipboardHistoryLimitRange.lowerBound),
                                         Self.clipboardHistoryLimitRange.upperBound)
        }
        set { defaults.set(newValue, forKey: ClipboardKey.historyLimit) }
    }

    var clipboardKeepFor: ClipboardKeepFor {
        get { defaults.string(forKey: ClipboardKey.keepFor).flatMap(ClipboardKeepFor.init) ?? .forever }
        set { defaults.set(newValue.rawValue, forKey: ClipboardKey.keepFor) }
    }

    /// Copying the same content again moves the existing entry to the top instead of adding a twin.
    var clipboardRejectDuplicates: Bool {
        get { defaults.object(forKey: ClipboardKey.rejectDuplicates) as? Bool ?? true }
        set { defaults.set(newValue, forKey: ClipboardKey.rejectDuplicates) }
    }

    var clipboardPinnedPlacement: ClipboardPinnedPlacement {
        get { defaults.string(forKey: ClipboardKey.pinnedPlacement).flatMap(ClipboardPinnedPlacement.init) ?? .beforeRecent }
        set { defaults.set(newValue.rawValue, forKey: ClipboardKey.pinnedPlacement) }
    }

    /// Seconds after which the Mac clipboard is emptied (history is untouched). 0 = never.
    var clipboardAutoClearSeconds: Int {
        get { defaults.integer(forKey: ClipboardKey.autoClearSeconds) }
        set { defaults.set(max(0, newValue), forKey: ClipboardKey.autoClearSeconds) }
    }

    var clipboardAutoClearOnlySensitive: Bool {
        get { defaults.object(forKey: ClipboardKey.autoClearOnlySensitive) as? Bool ?? false }
        set { defaults.set(newValue, forKey: ClipboardKey.autoClearOnlySensitive) }
    }

    /// Choosing an entry also pastes it into the previously active app (needs Accessibility).
    var clipboardPasteOnSelect: Bool {
        get { defaults.object(forKey: ClipboardKey.pasteOnSelect) as? Bool ?? false }
        set { defaults.set(newValue, forKey: ClipboardKey.pasteOnSelect) }
    }

    /// Choosing an entry also pins it.
    var clipboardCopyAndFavorite: Bool {
        get { defaults.object(forKey: ClipboardKey.copyAndFavorite) as? Bool ?? false }
        set { defaults.set(newValue, forKey: ClipboardKey.copyAndFavorite) }
    }

    /// Opening the library puts the cursor in the search field.
    var clipboardAutoFocusSearch: Bool {
        get { defaults.object(forKey: ClipboardKey.autoFocusSearch) as? Bool ?? false }
        set { defaults.set(newValue, forKey: ClipboardKey.autoFocusSearch) }
    }

    /// Global ⌥⇧Space opens the clipboard library in the island.
    var clipboardShortcutEnabled: Bool {
        get { defaults.object(forKey: ClipboardKey.shortcutEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: ClipboardKey.shortcutEnabled) }
    }
}
