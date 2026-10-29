import Foundation
import Testing
import WebKit

@testable import Brim

/// Opt-in network check: loads the real sites in the hidden page (fresh, non-persistent store)
/// and confirms the status script sees the signed-out login screen. (The test process is not a
/// real GUI app, so pages stay "hidden" here and the QR may not render; the app parks its window
/// so the page counts as visible.)
/// Run with `QS_LIVE_WEB=1 swift test --filter WebMessengerLiveTests`.
@MainActor
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["QS_LIVE_WEB"] != nil))
struct WebMessengerLiveTests {
  @Test(arguments: [ReplyChannel.whatsApp, .telegram])
  func signedOutSiteShowsLogin(channel: ReplyChannel) async throws {
    let profile = try #require(WebMessengerProfile.profile(for: channel))
    let driver = WKWebPageDriver(profile: profile, dataStore: .nonPersistent())
    defer { driver.tearDown() }
    driver.load(profile.home)
    var seen: [String] = []
    for _ in 0..<60 {
      try await Task.sleep(for: .seconds(1))
      let status = (try? await driver.run(profile.status, arguments: [:]))?.string ?? "error"
      if seen.last != status { seen.append(status) }
      if status == "login" || status == "unsupported" { break }
    }
    let language = try await driver.run(WebScript("live.lang", "return navigator.language;"), arguments: [:])
    let qr = try await driver.run(WebScript("live.qr", "const c = document.querySelector('canvas'); return c ? c.width + 'x' + c.height + ' ' + (c.getAttribute('aria-label') || '') : 'none';"), arguments: [:])
    print("[live] \(channel) qr canvas: \(qr)")
    print("[live] \(channel) status sequence: \(seen) language: \(language) url: \(driver.webView.url?.absoluteString ?? "-")")
    #expect(seen.last == "login")
  }

  /// The real WhatsApp login code goes through the panel's whole pipeline: page script, data URL,
  /// Core Image decode, crisp re-encode.
  @Test func whatsAppCodeReachesThePanel() async throws {
    let link = MemoryLink()
    let session = WebMessengerSession(profile: .whatsApp, link: link.link) {
      WKWebPageDriver(profile: $0, dataStore: .nonPersistent())
    }
    session.pollsAutomatically = false
    defer { session.driver?.tearDown() }
    var found: LinkCode?
    for _ in 0..<60 where found == nil {
      try await Task.sleep(for: .seconds(1))
      found = await session.linkSnapshot().code
    }
    let code = try #require(found)
    guard case .image(let png) = code else { Issue.record("expected the drawn code"); return }
    let text = try #require(ReplyQRImage.decode(png))
    print("[live] whatsapp code decoded: \(text.prefix(2))… (\(text.count) chars)")
    #expect(text.hasPrefix("2@") || text.contains("wa.me") || text.count > 20)
    #expect(ReplyQRImage.image(for: code) != nil)
  }
}
