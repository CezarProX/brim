// AppSettings+Updates.swift
// Brim

import Foundation

extension AppSettings {
    /// HTTPS appcast or JSON release feed. Empty (the default) means "no update source configured".
    var updateFeedURL: String {
        get { defaults.string(forKey: "updateFeedURL") ?? "" }
        set { defaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "updateFeedURL") }
    }

    /// Opt-in: look for a new version in the background about once a day (only with a feed set).
    var updateAutoCheck: Bool {
        get { defaults.object(forKey: "updateAutoCheck") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "updateAutoCheck") }
    }

    var updateLastCheck: Date? {
        get { defaults.object(forKey: "updateLastCheck") as? Date }
        set { defaults.set(newValue, forKey: "updateLastCheck") }
    }
}
