import AppKit
import Combine
import Foundation

/// Installation belongs to Sparkle. This model schedules quiet probes and exposes their result
/// to the island; neither background checks nor downloaded feed text can run an installer here.
@MainActor
final class AppUpdater: ObservableObject {
    static let shared = AppUpdater(driver: SparkleUpdateDriver())
    static let feedURL = URL(string: "https://github.com/CezarProX/brim/releases/latest/download/appcast.xml")!

    @Published private(set) var state = AppUpdateState.idle
    var availableVersion: String? { if case .available(let version) = state { version } else { nil } }
    var isChecking: Bool { state == .checking }
    var lastError: String? { if case .failed(let message) = state { message } else { nil } }

    private let settings: AppSettings
    private let driver: AppUpdateDriver
    private let now: () -> Date
    private let notify: (String) -> Void
    private var started = false
    private var timer: Timer?
    private var backgroundCheck = false

    init(settings: AppSettings = .shared, driver: AppUpdateDriver,
         now: @escaping () -> Date = { .now }, notify: ((String) -> Void)? = nil) {
        self.settings = settings
        self.driver = driver
        self.now = now
        self.notify = notify ?? Self.announce
        driver.onEvent = { [weak self] event in self?.receive(event) }
    }

    func startAutoCheck() {
        stop()
        guard ensureStarted(), settings.updateAutoCheck else { return }
        let timer = Timer(timeInterval: 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.probeIfDue() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        probeIfDue()
    }

    func stop() { timer?.invalidate(); timer = nil }

    /// User consent, signature validation, download, replacement and relaunch use Sparkle's UI.
    func checkInteractively() {
        guard ensureStarted(), driver.canCheckForUpdates else { return }
        backgroundCheck = false
        state = .checking
        driver.checkInteractively()
    }

    private func ensureStarted() -> Bool {
        if started { return true }
        do {
            try driver.start()
            started = true
            return true
        } catch {
            state = .failed(error.localizedDescription)
            return false
        }
    }

    private func probeIfDue() {
        guard settings.updateAutoCheck, driver.canCheckForUpdates, !isChecking else { return }
        if let last = settings.updateLastCheck, (0..<86_400).contains(now().timeIntervalSince(last)) { return }
        backgroundCheck = true
        state = .checking
        driver.probe()
    }

    private func receive(_ event: AppUpdateEvent) {
        switch event {
        case .found(let version):
            state = .available(version: version)
            if backgroundCheck && settings.hudUpdate { notify(version) }
        case .notFound:
            state = .upToDate
        case .finished(let error):
            if let error {
                state = .failed(error)
            } else {
                settings.updateLastCheck = now()
                if isChecking { state = .idle }
            }
            backgroundCheck = false
        }
    }

    private static func announce(_ version: String) {
        IslandFlashCenter.shared.show(
            "New version available", symbol: "arrow.down.circle.fill", tint: .green,
            duration: 10, detail: "Brim \(version)",
            action: HUDAction(title: L10n.tr("Install Update…"), symbol: "arrow.down.circle.fill") {
                NotchShelfController.shared.dismissShelf()
                AppUpdater.shared.checkInteractively()
            }, shortTitle: L10n.tr("Update %@", version))
    }
}

enum AppUpdateState: Equatable {
    case idle, checking, upToDate
    case available(version: String)
    case failed(String)
}

enum AppUpdateEvent {
    case found(version: String)
    case notFound
    case finished(error: String?)
}

@MainActor
protocol AppUpdateDriver: AnyObject {
    var canCheckForUpdates: Bool { get }
    var onEvent: ((AppUpdateEvent) -> Void)? { get set }
    func start() throws
    func probe()
    func checkInteractively()
}
