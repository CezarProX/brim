import Foundation
import Testing

@testable import Brim

@MainActor
struct NotificationTrustTests {
  private func settings() -> AppSettings {
    let defaults = UserDefaults(suiteName: "NotificationTrustTests-\(UUID().uuidString)")!
    let settings = AppSettings(defaults: defaults)
    settings.notificationHUDEnabled = true
    return settings
  }

  @Test func startsReadingBannersOnceAccessibilityIsGranted() {
    var trusted = false
    var prompts = 0
    let model = NotificationHUDModel(
      settings: settings(), trust: .init(isTrusted: { trusted }, request: { prompts += 1 }))
    defer { model.stop() }

    model.start()
    #expect(model.needsAccessibility)
    #expect(prompts == 1)

    model.checkTrust()
    #expect(model.needsAccessibility)

    trusted = true
    model.checkTrust()
    #expect(!model.needsAccessibility)
    #expect(prompts == 1)
  }
}
