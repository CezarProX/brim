// UpdateChecker.swift
// Brim
//
// Honest update check: nothing is contacted unless the user configured an HTTPS feed in
// Settings > About. The check only reports; it never downloads or installs anything itself.

import AppKit
import Foundation

@MainActor
final class UpdateChecker {
    static let shared = UpdateChecker()
    typealias Fetch = @Sendable (URL) async throws -> Data
    private(set) var isChecking = false
    private var timer: Timer?
    private init() {}

    nonisolated static let defaultFetch: Fetch = { url in
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 15
        var request = URLRequest(url: url)
        request.setValue("Brim", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession(configuration: config).data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        guard data.count < 1_000_000 else { throw URLError(.dataLengthExceedsMaximum) }
        return data
    }

    /// Pure-ish core: injectable feed text, version and fetcher so it can be tested.
    func check(feed: String, current: String, fetch: @escaping Fetch = UpdateChecker.defaultFetch) async -> UpdateOutcome {
        let trimmed = feed.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .notConfigured }
        guard let url = UpdateFeed.validatedURL(trimmed) else { return .invalidFeed }
        do {
            let data = try await fetch(url)
            guard let release = UpdateFeed.parse(data) else {
                return .failed("The feed didn't contain a readable version.")
            }
            return UpdateDecision.decide(current: current, release: release)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    // MARK: App integration

    /// Menu action: tells the user the truth in every state.
    func checkInteractively() {
        guard !isChecking else { return }
        let settings = AppSettings.shared
        let current = SettingsUtilities.appVersion
        if settings.updateFeedURL.isEmpty { return present(.notConfigured, current: current) }
        isChecking = true
        Task {
            let outcome = await check(feed: settings.updateFeedURL, current: current)
            isChecking = false
            settings.updateLastCheck = .now
            present(outcome, current: current)
        }
    }

    func startAutoCheck() {
        timer?.invalidate()
        timer = nil
        let settings = AppSettings.shared
        guard settings.updateAutoCheck, !settings.updateFeedURL.isEmpty else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.backgroundCheckIfDue() }
        }
        backgroundCheckIfDue()
    }

    private func backgroundCheckIfDue() {
        let settings = AppSettings.shared
        guard settings.updateAutoCheck, !isChecking else { return }
        if let last = settings.updateLastCheck, Date.now.timeIntervalSince(last) < 86_400 { return }
        isChecking = true
        Task {
            let outcome = await check(feed: settings.updateFeedURL, current: SettingsUtilities.appVersion)
            isChecking = false
            settings.updateLastCheck = .now
            if case .available(let release) = outcome, settings.hudUpdate { flash(release) }  // quiet otherwise
        }
    }

    private func flash(_ release: UpdateRelease) {
        IslandFlashCenter.shared.show(
            "New version available", symbol: "arrow.down.circle.fill", tint: .green,
            duration: 6, detail: "Brim \(release.version)",
            action: HUDAction(title: "Details", symbol: "info.circle") { [weak self] in
                self?.present(.available(release), current: SettingsUtilities.appVersion)
            }, shortTitle: L10n.tr("Update %@", release.version))
    }

    private func present(_ outcome: UpdateOutcome, current: String) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.addButton(withTitle: L10n.tr("OK"))
        switch outcome {
        case .notConfigured:
            alert.messageText = L10n.tr("Automatic updates aren't set up for this build")
            alert.informativeText = L10n.tr("You have Brim %@. To check for new versions, add an HTTPS update feed in Settings > About.", current)
        case .invalidFeed:
            alert.messageText = L10n.tr("The update feed address isn't valid")
            alert.informativeText = L10n.tr("It must be an https:// address. Fix it in Settings > About.")
        case .upToDate(let version):
            alert.messageText = L10n.tr("You're up to date")
            alert.informativeText = L10n.tr("Brim %@ is the latest version in your update feed.", version)
        case .failed(let reason):
            alert.messageText = L10n.tr("Couldn't check for updates")
            alert.informativeText = reason
        case .available(let release):
            flash(release)
            alert.messageText = L10n.tr("Brim %@ is available", release.version)
            alert.informativeText = L10n.tr("You have %@.", current) + (release.notes.isEmpty ? "" : "\n\n" + release.notes.prefix(1200))
            if let url = release.downloadURL {
                alert.addButton(withTitle: L10n.tr("Download"))
                if alert.runModal() == .alertSecondButtonReturn { NSWorkspace.shared.open(url) }
                return
            }
        }
        alert.runModal()
    }
}
