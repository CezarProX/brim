import Foundation
import Sparkle

/// The only installation path. The fixed signed feed and bundled public key deliberately ignore
/// old custom JSON feed preferences and imported settings. Sparkle verifies before extraction.
@MainActor
final class SparkleUpdateDriver: NSObject, AppUpdateDriver, SPUUpdaterDelegate {
    var onEvent: ((AppUpdateEvent) -> Void)?
    private var foundNoUpdate = false
    private lazy var controller = SPUStandardUpdaterController(
        startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
    var canCheckForUpdates: Bool { controller.updater.canCheckForUpdates }

    func start() throws {
        guard Bundle.main.bundleURL.pathExtension == "app",
              Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String == AppUpdater.feedURL.absoluteString,
              let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              Data(base64Encoded: key)?.count == 32,
              Bundle.main.object(forInfoDictionaryKey: "SURequireSignedFeed") as? Bool == true,
              Bundle.main.object(forInfoDictionaryKey: "SUVerifyUpdateBeforeExtraction") as? Bool == true else {
            throw ConfigurationError.notPackaged
        }
        try controller.updater.start()
    }

    func probe() {
        foundNoUpdate = false
        controller.updater.checkForUpdateInformation()
    }

    func checkInteractively() {
        foundNoUpdate = false
        controller.checkForUpdates(nil)
    }

    func feedURLString(for updater: SPUUpdater) -> String? { AppUpdater.feedURL.absoluteString }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        onEvent?(.found(version: item.displayVersionString))
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        foundNoUpdate = true
        onEvent?(.notFound)
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        // Sparkle reports "no update" through an NSError too; that is a successful check.
        onEvent?(.finished(error: foundNoUpdate ? nil : error?.localizedDescription))
    }

    private enum ConfigurationError: LocalizedError {
        case notPackaged
        var errorDescription: String? { L10n.tr("Install a release build of Brim to use signed updates.") }
    }
}
