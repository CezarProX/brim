import AppKit
import Foundation
import Testing

@testable import Brim

/// A scripted stand-in for the web page. Each script name maps to a queue of answers; the last
/// answer repeats. Records every call so tests can check order and arguments.
@MainActor
final class FakeWebPage: WebPageDriving {
  var answers: [String: [WebValue]] = [:]
  var hang: Set<String> = []
  private(set) var calls: [(name: String, source: String, arguments: [String: WebArgument])] = []
  private(set) var loaded: [URL] = []
  private(set) var erased = false
  private(set) var tornDown = false

  var pageView: NSView? { nil }
  func load(_ url: URL) { loaded.append(url) }
  func returnToKeepAlive() {}
  func eraseData() async { erased = true }
  func tearDown() { tornDown = true }

  func run(_ script: WebScript, arguments: [String: WebArgument]) async throws -> WebValue {
    calls.append((script.name, script.source, arguments))
    if hang.contains(script.name) { try await Task.sleep(for: .seconds(5)) }
    guard var queue = answers[script.name], let first = queue.first else { return .none }
    if queue.count > 1 { queue.removeFirst(); answers[script.name] = queue }
    return first
  }

  var callNames: [String] { calls.map(\.name) }

  /// A page where everything works: logged in, chat in the list, typing and sending succeed.
  static func happy(_ prefix: String = "whatsapp") -> FakeWebPage {
    let page = FakeWebPage()
    page.answers = [
      "\(prefix).status": [.string("connected")],
      "\(prefix).openChat": [.string("clicked")],
      "\(prefix).activeChat": [.bool(true)],
      "\(prefix).compose": [.string("ok")],
      "\(prefix).send": [.number(3)],
      "\(prefix).confirm": [.string("pending"), .string("sent")],
    ]
    return page
  }
}

extension Result where Success == Void, Failure == ReplyError {
  var replyError: ReplyError? {
    if case .failure(let error) = self { return error }
    return nil
  }
  var isReplySuccess: Bool { replyError == nil }
}

final class MemoryLink {
  var linked = false
  var link: ReplyLink { ReplyLink(get: { self.linked }, set: { self.linked = $0 }) }
}

let fastPacing = ReplyPacing(readyAttempts: 3, chatAttempts: 3, confirmAttempts: 3, interval: .zero, scriptTimeout: .seconds(2))

// MARK: - Routing

struct ReplyRoutingTests {
  @Test(arguments: [
    ("com.apple.MobileSMS", ReplyChannel.messages), ("net.whatsapp.WhatsApp", .whatsApp),
    ("desktop.WhatsApp", .whatsApp), ("net.whatsapp.WhatsAppSMB", .whatsApp),
    ("ru.keepcoder.Telegram", .telegram), ("org.telegram.desktop", .telegram),
  ])
  func routesBundleIDs(id: String, channel: ReplyChannel) {
    #expect(ReplyChannel.route(bundleID: id, appName: "x") == channel)
  }

  @Test func unknownAppsHaveNoChannel() {
    #expect(ReplyChannel.route(bundleID: "com.apple.mail", appName: "WhatsApp") == nil)
    #expect(ReplyChannel.route(bundleID: nil, appName: "Mail") == nil)
  }

  @Test func fallsBackToAppNameWithoutBundleID() {
    #expect(ReplyChannel.route(bundleID: nil, appName: "WhatsApp") == .whatsApp)
    #expect(ReplyChannel.route(bundleID: nil, appName: "Telegram") == .telegram)
    #expect(ReplyChannel.route(bundleID: nil, appName: "Messages") == .messages)
  }

  @Test func replyBarShowsForRoutedAppsEvenBeforeLinking() {
    #expect(NotificationContent(bundleID: "net.whatsapp.WhatsApp", appName: "WhatsApp", title: "Anna").supportsReply)
    #expect(NotificationContent(bundleID: "ru.keepcoder.Telegram", appName: "Telegram", title: "Anna").supportsReply)
    #expect(NotificationContent(bundleID: NotificationApps.messages, appName: "Messages", title: "Anna").supportsReply)
    #expect(!NotificationContent(bundleID: "net.whatsapp.WhatsApp", appName: "WhatsApp").supportsReply)
    #expect(!NotificationContent(bundleID: "com.apple.mail", appName: "Mail", title: "Anna").supportsReply)
  }

  @Test func availabilityPersistsPerChannel() throws {
    let suite = try #require(UserDefaults(suiteName: "reply-test-\(UUID().uuidString)"))
    let saved = ReplyAvailability.defaults
    ReplyAvailability.defaults = suite
    defer { ReplyAvailability.defaults = saved }
    #expect(ReplyAvailability.connected == [.messages])
    ReplyAvailability.setConnected(true, for: .whatsApp)
    #expect(ReplyAvailability.connected == [.messages, .whatsApp])
    ReplyAvailability.setConnected(false, for: .messages)
    #expect(ReplyAvailability.isConnected(.messages))
  }

  @Test func placeholdersNameTheApp() {
    #expect(ReplyChannel.messages.placeholder == "iMessage…")
    #expect(ReplyChannel.whatsApp.placeholder == "WhatsApp…")
    #expect(ReplyChannel.telegram.placeholder == "Telegram…")
  }

  @Test func chatNameCandidates() {
    #expect(ReplyChatNames.candidates(title: "Anna", subtitle: "") == ["Anna"])
    #expect(ReplyChatNames.candidates(title: "Anna @ Family", subtitle: "") == ["Family", "Anna", "Anna @ Family"])
    #expect(ReplyChatNames.candidates(title: "Family", subtitle: "Anna") == ["Family", "Anna"])
    #expect(ReplyChatNames.candidates(title: "~ Bob\u{200E}", subtitle: "Bob") == ["Bob"])
    #expect(ReplyChatNames.candidates(title: "  ", subtitle: "") == [])
  }

  @Test func messagesFailuresMapToReplyErrors() {
    #expect(ReplyError.fromMessages(.empty) == .empty)
    #expect(ReplyError.fromMessages(.scriptFailed("execution error (-1743)")) == .messagesAutomationDenied)
    #expect(ReplyError.fromMessages(.scriptFailed("No conversation found for x")) == .messagesConversationMissing)
    #expect(ReplyError.fromMessages(.scriptFailed("boom")) == .failed)
    #expect(ReplyError.notConnected(.whatsApp).message == "Connect WhatsApp in Settings to reply")
    #expect(ReplyError.notConnected(.telegram).message == "Connect Telegram in Settings to reply")
    #expect(ReplyError.chatNotFound.message == "Couldn't find this chat")
  }
}

// MARK: - Transport fakes

@MainActor
final class RecordingTransport: ReplyTransport {
  var sent: [(String, String)] = []
  var result: Result<Void, ReplyError> = .success(())
  func send(_ text: String, to item: NotificationContent) async -> Result<Void, ReplyError> {
    sent.append((text, item.title))
    return result
  }
}

// MARK: - Argument encoding

@MainActor
struct ReplyArgumentEncodingTests {
  nonisolated static let hostile = [
    #"\"); window.__pwned = 1; (\""#, "</script><script>alert(1)</script>", "${alert(1)}", "`; alert(1); `",
    "line\nbreak\u{2028}sep", "-flag",
  ]

  @Test(arguments: hostile)
  func textTravelsAsAnArgumentNeverAsSource(text: String) async throws {
    let page = FakeWebPage.happy()
    try await WebReplySender(driver: page, profile: .whatsApp, pacing: fastPacing).send(text: text, names: [text])
    for call in page.calls {
      #expect(!call.source.contains(text), "\(call.name) source must not contain user input")
    }
    let compose = try #require(page.calls.first { $0.name == "whatsapp.compose" })
    #expect(compose.arguments == ["text": .string(text)])
    let open = try #require(page.calls.first { $0.name == "whatsapp.openChat" })
    #expect(open.arguments == ["names": .strings([text])])
  }

  @Test func scriptSourcesAreFixed() {
    for profile in [WebMessengerProfile.whatsApp, .telegram] {
      let scripts = [profile.status, profile.openChat, profile.search, profile.activeChat, profile.compose,
                     profile.send, profile.confirm, profile.closeChat]
      #expect(Set(scripts.map(\.name)).count == scripts.count)
      #expect(scripts.allSatisfy { $0.source.hasPrefix(WebScriptPrelude.source) })
    }
  }

  @Test func argumentsBridgeAsPlainValues() {
    #expect(WebArgument.string("a").javaScriptValue as? String == "a")
    #expect(WebArgument.strings(["a", "b"]).javaScriptValue as? [String] == ["a", "b"])
    #expect(WebArgument.number(2).javaScriptValue as? Double == 2)
    #expect(WebValue(NSNumber(value: true)) == .bool(true))
    #expect(WebValue(NSNumber(value: 3)) == .number(3))
    #expect(WebValue("x") == .string("x"))
    #expect(WebValue(nil) == .none)
  }

  @Test func keepAliveWindowsLeaveOnePixelOnScreenInSeparateCorners() {
    let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let size = WebKeepAliveWindow.size
    for slot in [0, 1] {
      let frame = CGRect(origin: WebKeepAliveWindow.parkedOrigin(screen: screen, size: size, slot: slot), size: size)
      let visible = frame.intersection(screen)
      #expect(visible.width == 1 && visible.height == 1, "slot \(slot)")
    }
    let a = WebKeepAliveWindow.parkedOrigin(screen: screen, size: size, slot: 0)
    let b = WebKeepAliveWindow.parkedOrigin(screen: screen, size: size, slot: 1)
    #expect(CGRect(origin: a, size: size).intersection(CGRect(origin: b, size: size)).isEmpty)
  }

  @Test func navigationStaysOnTheMessengerSite() {
    let hosts = WKWebPageDriver.allowedHosts(for: WebMessengerProfile.whatsApp.home)
    #expect(hosts == ["web.whatsapp.com", "whatsapp.com"])
    #expect(WKWebPageDriver.isAllowed(URL(string: "https://web.whatsapp.com/"), hosts: hosts))
    #expect(WKWebPageDriver.isAllowed(URL(string: "https://static.whatsapp.com/x.js"), hosts: hosts))
    #expect(WKWebPageDriver.isAllowed(URL(string: "about:blank"), hosts: hosts))
    #expect(!WKWebPageDriver.isAllowed(URL(string: "http://web.whatsapp.com/"), hosts: hosts))
    #expect(!WKWebPageDriver.isAllowed(URL(string: "https://evilwhatsapp.com/"), hosts: hosts))
    #expect(!WKWebPageDriver.isAllowed(URL(string: "https://example.com/"), hosts: hosts))
  }
}
