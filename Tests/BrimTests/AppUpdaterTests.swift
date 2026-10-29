import Foundation
import Testing

@testable import Brim

@MainActor
struct AppUpdaterTests {
    private func settings() -> AppSettings {
        AppSettings(defaults: UserDefaults(suiteName: "brim.updates.\(UUID().uuidString)")!)
    }

    @Test func defaultsEnableDailyChecksWithoutAUserSuppliedFeed() {
        #expect(settings().updateAutoCheck)
    }

    @Test func backgroundProbeOffersAnUpdateWithoutInstallingIt() {
        let driver = UpdateDriverStub()
        var offered: [String] = []
        let updater = AppUpdater(settings: settings(), driver: driver, notify: { offered.append($0) })
        updater.startAutoCheck()
        defer { updater.stop() }
        #expect(driver.probes == 1)
        #expect(driver.interactiveChecks == 0)
        driver.onEvent?(.found(version: "1.2.0"))
        driver.onEvent?(.finished(error: nil))
        #expect(updater.availableVersion == "1.2.0")
        #expect(offered == ["1.2.0"])
        updater.checkInteractively()
        #expect(driver.interactiveChecks == 1)
    }

    @Test func disabledBackgroundChecksStillAllowExplicitUpdates() {
        let preferences = settings()
        preferences.updateAutoCheck = false
        let driver = UpdateDriverStub()
        let updater = AppUpdater(settings: preferences, driver: driver, notify: { _ in })
        updater.startAutoCheck()
        defer { updater.stop() }
        #expect(driver.probes == 0)
        updater.checkInteractively()
        #expect(driver.interactiveChecks == 1)
    }

    @Test func aRecentSuccessfulCheckSkipsAnotherProbe() {
        let preferences = settings()
        preferences.updateLastCheck = .now
        let driver = UpdateDriverStub()
        let updater = AppUpdater(settings: preferences, driver: driver, notify: { _ in })
        updater.startAutoCheck()
        defer { updater.stop() }
        #expect(driver.probes == 0)
    }

    @Test func busyDriverDoesNotStartAnotherUpdateSession() {
        let driver = UpdateDriverStub()
        driver.canCheckForUpdates = false
        let updater = AppUpdater(settings: settings(), driver: driver, notify: { _ in })
        updater.startAutoCheck()
        defer { updater.stop() }
        updater.checkInteractively()
        #expect(driver.probes == 0)
        #expect(driver.interactiveChecks == 0)
        #expect(!updater.isChecking)
    }

    @Test func networkFailureIsVisibleAndAllowsRetry() {
        let preferences = settings()
        let driver = UpdateDriverStub()
        let updater = AppUpdater(settings: preferences, driver: driver, notify: { _ in })
        updater.startAutoCheck()
        defer { updater.stop() }
        driver.onEvent?(.finished(error: "Offline"))
        #expect(updater.lastError == "Offline")
        #expect(!updater.isChecking)
        #expect(preferences.updateLastCheck == nil)
        updater.checkInteractively()
        #expect(driver.interactiveChecks == 1)
    }

    @Test func badConfigurationFailsWithoutStartingANetworkRequest() {
        let driver = UpdateDriverStub()
        driver.startError = URLError(.badURL)
        let updater = AppUpdater(settings: settings(), driver: driver, notify: { _ in })
        updater.startAutoCheck()
        defer { updater.stop() }
        #expect(updater.lastError != nil)
        #expect(driver.probes == 0)
        #expect(driver.interactiveChecks == 0)
    }
}

@MainActor
private final class UpdateDriverStub: AppUpdateDriver {
    var onEvent: ((AppUpdateEvent) -> Void)?
    var canCheckForUpdates = true
    var startError: Error?
    var probes = 0
    var interactiveChecks = 0
    func start() throws { if let startError { throw startError } }
    func probe() { probes += 1 }
    func checkInteractively() { interactiveChecks += 1 }
}

@MainActor
struct SparkleConfigurationTests {
    @Test func packagedFeedRequiresSignaturesAndExplicitInstallation() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("Resources/Info.plist"))
        let info = try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        #expect(info["SUFeedURL"] as? String == AppUpdater.feedURL.absoluteString)
        let key = try #require(info["SUPublicEDKey"] as? String)
        #expect(Data(base64Encoded: key)?.count == 32)
        #expect(info["SURequireSignedFeed"] as? Bool == true)
        #expect(info["SUVerifyUpdateBeforeExtraction"] as? Bool == true)
        #expect(info["SUAllowsAutomaticUpdates"] as? Bool == false)
        #expect(info["SUEnableAutomaticChecks"] as? Bool == false)
    }

    @Test func nativeDelegateCallbacksAreExposedToSparkle() {
        let driver = SparkleUpdateDriver()
        for selector in ["feedURLStringForUpdater:", "updater:didFindValidUpdate:",
                         "updaterDidNotFindUpdate:", "updater:didFinishUpdateCycleForUpdateCheck:error:"] {
            #expect(driver.responds(to: NSSelectorFromString(selector)), "Missing Sparkle callback: \(selector)")
        }
    }

    @Test func unpackagedExecutableCannotRunAnInstaller() {
        do {
            try SparkleUpdateDriver().start()
            Issue.record("Installer must reject an unpackaged test executable")
        } catch {
            #expect(!error.localizedDescription.isEmpty)
        }
    }
}
