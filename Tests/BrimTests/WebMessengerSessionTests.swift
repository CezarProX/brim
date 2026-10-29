import Foundation
import Testing

@testable import Brim

/// Connection and send state machine of the hidden web session, driven by a fake page.
@MainActor
struct WebMessengerSessionTests {
  private func session(_ page: FakeWebPage, linked: Bool = true, pacing: ReplyPacing = fastPacing)
    -> (WebMessengerSession, MemoryLink) {
    let link = MemoryLink()
    link.linked = linked
    let s = WebMessengerSession(profile: .whatsApp, pacing: pacing, link: link.link) { _ in page }
    s.pollsAutomatically = false
    return (s, link)
  }

  // MARK: Connection

  @Test func activateLoadsHomeOnceAndStartsLoading() {
    let page = FakeWebPage()
    let (s, _) = session(page)
    #expect(s.state == .off)
    s.activate()
    s.activate()
    #expect(s.state == .loading)
    #expect(page.loaded == [WebMessengerProfile.whatsApp.home])
  }

  @Test func statusMovesBetweenLoginAndConnected() async {
    let page = FakeWebPage()
    page.answers["whatsapp.status"] = [.string("login"), .string("connected"), .string("loading"), .string("login"), .string("login")]
    let (s, link) = session(page, linked: false)
    s.activate()
    await s.refreshStatus()
    #expect(s.state == .needsLogin && !link.linked)
    await s.refreshStatus()
    #expect(s.state == .connected && link.linked)
    await s.refreshStatus()
    #expect(s.state == .connected, "a reload blip keeps the session connected")
    await s.refreshStatus()
    #expect(s.state == .connected && link.linked, "one login screen while linked is not a logout yet")
    await s.refreshStatus()
    #expect(s.state == .needsLogin && !link.linked, "a session revoked from the phone unlinks")
  }

  @Test func disconnectErasesDataAndUnlinks() async {
    let page = FakeWebPage()
    page.answers["whatsapp.status"] = [.string("connected")]
    let (s, link) = session(page)
    s.activate()
    await s.refreshStatus()
    await s.disconnect()
    #expect(page.erased && page.tornDown)
    #expect(s.state == .off && !link.linked && s.driver == nil)
  }

  // MARK: Sending

  @Test func happyPathRunsEveryStepInOrder() async {
    let page = FakeWebPage.happy()
    let (s, _) = session(page)
    let result = await s.send("  hi there  ", names: ["Anna"])
    #expect(result.isReplySuccess)
    #expect(page.callNames == [
      "whatsapp.status", "whatsapp.openChat", "whatsapp.activeChat", "whatsapp.compose", "whatsapp.send",
      "whatsapp.confirm", "whatsapp.confirm", "whatsapp.closeChat",
    ])
    #expect(page.calls[3].arguments["text"] == .string("hi there"))
    #expect(page.calls[5].arguments["before"] == .number(3))
    #expect(s.state == .connected && !s.isSending)
  }

  @Test func alreadyOpenChatSkipsClicking() async {
    let page = FakeWebPage.happy()
    page.answers["whatsapp.openChat"] = [.string("open")]
    let (s, _) = session(page)
    #expect(await s.send("hi", names: ["Anna"]).isReplySuccess)
    #expect(!page.callNames.contains("whatsapp.activeChat"))
  }

  @Test func fallsBackToSearchWhenTheChatIsNotListed() async {
    let page = FakeWebPage.happy()
    page.answers["whatsapp.openChat"] = [.string(""), .string(""), .string("clicked")]
    page.answers["whatsapp.search"] = [.string("typed")]
    let (s, _) = session(page)
    #expect(await s.send("hi", names: ["Anna"]).isReplySuccess)
    #expect(page.callNames.filter { $0 == "whatsapp.openChat" }.count == 3)
  }

  @Test func unlinkedSessionRefusesWithoutLoadingAPage() async {
    let page = FakeWebPage.happy()
    let (s, _) = session(page, linked: false)
    #expect(await s.send("hi", names: ["Anna"]).replyError == .notConnected(.whatsApp))
    #expect(page.loaded.isEmpty && s.state == .off)
  }

  @Test func linkedSessionStartsThePageOnFirstReply() async {
    let page = FakeWebPage.happy()
    let (s, _) = session(page)
    #expect(await s.send("hi", names: ["Anna"]).isReplySuccess)
    #expect(page.loaded.count == 1)
  }

  @Test func loginScreenMeansNotConnected() async {
    let page = FakeWebPage.happy()
    page.answers["whatsapp.status"] = [.string("login")]
    let (s, link) = session(page)
    #expect(await s.send("hi", names: ["Anna"]).replyError == .notConnected(.whatsApp))
    #expect(s.state == .needsLogin && !link.linked)
  }

  @Test func pageThatNeverLoadsIsNotReady() async {
    let page = FakeWebPage.happy()
    page.answers["whatsapp.status"] = [.string("loading")]
    let (s, _) = session(page)
    #expect(await s.send("hi", names: ["Anna"]).replyError == .notReady(.whatsApp))
  }

  @Test func failures() async {
    let cases: [(String, WebValue, ReplyError)] = [
      ("whatsapp.activeChat", .bool(false), .chatNotFound),
      ("whatsapp.compose", .string("nocomposer"), .composerMissing),
      ("whatsapp.compose", .string("empty"), .composerMissing),
      ("whatsapp.send", .number(-1), .sendButtonMissing),
      ("whatsapp.confirm", .string("pending"), .unconfirmed),
    ]
    for (script, answer, expected) in cases {
      let page = FakeWebPage.happy()
      page.answers[script] = [answer]
      let (s, _) = session(page)
      #expect(await s.send("hi", names: ["Anna"]).replyError == expected, "\(script)")
      #expect(!s.isSending)
    }
  }

  @Test func unknownChatWithoutSearchIsNotFound() async {
    let page = FakeWebPage.happy()
    page.answers["whatsapp.openChat"] = [.string("")]
    page.answers["whatsapp.search"] = [.string("")]
    let (s, _) = session(page)
    #expect(await s.send("hi", names: ["Nobody"]).replyError == .chatNotFound)
    #expect(await s.send("hi", names: []).replyError == .chatNotFound)
  }

  @Test func emptyTextIsRejected() async {
    let (s, _) = session(FakeWebPage.happy())
    #expect(await s.send("  \n ", names: ["Anna"]).replyError == .empty)
  }

  @Test func hungScriptTimesOut() async {
    let page = FakeWebPage.happy()
    page.hang = ["whatsapp.compose"]
    var pacing = fastPacing
    pacing.scriptTimeout = .milliseconds(60)
    let (s, _) = session(page, pacing: pacing)
    #expect(await s.send("hi", names: ["Anna"]).replyError == .timeout)
    #expect(!s.isSending)
  }

  @Test func secondReplyWhileSendingIsBusy() async {
    let page = FakeWebPage.happy()
    page.hang = ["whatsapp.compose"]
    var pacing = fastPacing
    pacing.scriptTimeout = .milliseconds(300)
    let (s, _) = session(page, pacing: pacing)
    async let first = s.send("one", names: ["Anna"])
    try? await Task.sleep(for: .milliseconds(30))
    #expect(s.isSending)
    #expect(await s.send("two", names: ["Anna"]).replyError == .busy)
    #expect(await first.replyError == .timeout)
  }
}

/// The island card's reply state, with a fake transport.
@MainActor
struct NotificationReplyModelTests {
  private func model(_ transport: RecordingTransport) throws -> NotificationHUDModel {
    let suite = try #require(UserDefaults(suiteName: "reply-model-\(UUID().uuidString)"))
    let settings = AppSettings(defaults: suite)
    settings.notificationHUDEnabled = true
    settings.notificationHUDHideWhileSharing = false
    return NotificationHUDModel(settings: settings, replies: ReplyCoordinator(messages: transport, sessions: { _ in nil }))
  }

  private let message = NotificationContent(bundleID: NotificationApps.messages, appName: "Messages", title: "Anna", body: "hi")

  @Test func failureShowsTheErrorMessage() async throws {
    let transport = RecordingTransport()
    transport.result = .failure(.chatNotFound)
    let m = try model(transport)
    m.ingest(message)
    m.reply("hello", to: message)
    #expect(m.replyState == .sending)
    for _ in 0..<50 where m.replyState == .sending { try await Task.sleep(for: .milliseconds(10)) }
    #expect(m.replyState == .failed("Couldn't find this chat"))
    #expect(transport.sent.map(\.0) == ["hello"])
  }

  @Test func successMarksSent() async throws {
    let transport = RecordingTransport()
    let m = try model(transport)
    m.ingest(message)
    m.reply("hello", to: message)
    for _ in 0..<50 where m.replyState == .sending { try await Task.sleep(for: .milliseconds(10)) }
    #expect(m.replyState == .sent)
  }

  @Test func unsupportedAppsNeverSend() throws {
    let transport = RecordingTransport()
    let m = try model(transport)
    let mail = NotificationContent(bundleID: "com.apple.mail", appName: "Mail", title: "x", body: "y")
    m.ingest(mail)
    m.reply("hello", to: mail)
    #expect(m.replyState == .idle && transport.sent.isEmpty)
  }
}
