// UpdateChecker.swift
// Brim
//
// Legacy feed parsing remains testable; app update actions use the signed Sparkle installer.

import AppKit
import Foundation

@MainActor
final class UpdateChecker {
    static let shared = UpdateChecker()
    typealias Fetch = @Sendable (URL) async throws -> Data
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

    func checkInteractively() { AppUpdater.shared.checkInteractively() }

    func startAutoCheck() { AppUpdater.shared.startAutoCheck() }
}
