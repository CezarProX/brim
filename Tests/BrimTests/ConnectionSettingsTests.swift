import Foundation
import Testing
@testable import Brim

struct ConnectionSettingsTests {
    @Test func callDiscoveryDefaultsOnAndExplicitPausePersists() throws {
        let suite = "Brim.ConnectionTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        #expect(settings.callIntegrationEnabled)
        #expect(settings.enabledMusicSources.isEmpty)
        settings.callIntegrationEnabled = true
        settings.enabledMusicSources = ["spotify", "music", "spotify"]
        let reopened = AppSettings(defaults: defaults)
        #expect(reopened.callIntegrationEnabled)
        #expect(reopened.enabledMusicSources == ["music", "spotify"])
        reopened.enabledMusicSources = []
        reopened.callIntegrationEnabled = false
        #expect(settings.enabledMusicSources.isEmpty)
        #expect(!settings.callIntegrationEnabled)
    }
}
