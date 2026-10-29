// AppSettings+Updates.swift
// Brim

import Foundation

extension AppSettings {
    /// Legacy check-only feed, retained for settings compatibility. Installations use the signed official feed.
    var updateFeedURL: String {
        get { defaults.string(forKey: "updateFeedURL") ?? "" }
        set { defaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "updateFeedURL") }
    }

    /// Check official signed releases once a day. Installation still requires an explicit user action.
    var updateAutoCheck: Bool {
        get { defaults.object(forKey: "updateAutoCheck") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "updateAutoCheck") }
    }

    var updateLastCheck: Date? {
        get { defaults.object(forKey: "updateLastCheck") as? Date }
        set { defaults.set(newValue, forKey: "updateLastCheck") }
    }
}
