import AppKit
import Foundation
import Testing

@testable import Brim

/// A scripted messenger session for the coordinator and the link panel.
@MainActor
final class FakeLinkSession: LinkableSession {
  let channel: ReplyChannel
  var isLinked = false
  var isReady = false
  var snapshots: [LinkSnapshot] = [LinkSnapshot(status: .loading)]
  var readiness: [SessionReadiness] = [.ready]
  var sendResults: [Result<Void, ReplyError>] = [.success(())]
  var readyDelay: Duration = .zero
  private(set) var sent: [(text: String, names: [String], afterLink: Bool)] = []
  private(set) var activations = 0
  private(set) var reloads = 0
  private(set) var suspends = 0

  init(channel: ReplyChannel = .whatsApp) { self.channel = channel }

  func activate() { activations += 1 }
  func reload() { reloads += 1 }
  func suspend() { suspends += 1 }

  func linkSnapshot() async -> LinkSnapshot {
    let next = Self.pop(&snapshots)
    if next.status == .connected { isLinked = true; isReady = true }
    return next
  }

  func waitUntilReady(timeout: Duration) async -> SessionReadiness {
    try? await Task.sleep(for: readyDelay)
    let result = Self.pop(&readiness)
    if result == .ready { isReady = true }
    if result == .needsLogin { isLinked = false }
    return result
  }

  func send(_ text: String, names: [String], afterLink: Bool) async -> Result<Void, ReplyError> {
    sent.append((text, names, afterLink))
    return Self.pop(&sendResults)
  }

  private static func pop<T>(_ queue: inout [T]) -> T {
    queue.count > 1 ? queue.removeFirst() : queue[0]
  }
}

@MainActor
func waitFor(_ condition: () -> Bool, timeout: Duration = .seconds(2)) async {
  let clock = ContinuousClock()
  let deadline = clock.now + timeout
  while !condition(), clock.now < deadline { try? await Task.sleep(for: .milliseconds(5)) }
}

private let code = LinkCode.payload("2@demo-code")

// MARK: - Phases

struct LinkPhaseTests {
  private func next(_ current: LinkPhase, _ status: WebPageStatus, code: LinkCode? = nil, polls: Int = 0,
                    password: Bool = false) -> LinkPhase {
    LinkPhase.next(after: current, snapshot: LinkSnapshot(status: status, code: code, needsPassword: password),
                   codelessPolls: polls)
  }

  @Test func walksFromLoadingToCodeToLinkingToSuccess() {
    #expect(next(.loadingCode, .loading) == .loadingCode)
    #expect(next(.loadingCode, .login) == .loadingCode)
    #expect(next(.loadingCode, .login, code: code) == .code(code))
    #expect(next(.code(code), .loading) == .linking, "the code went away: the phone scanned it")
    #expect(next(.linking, .loading) == .linking)
    #expect(next(.linking, .connected) == .success)
  }

  @Test func keepsTheLastCodeWhileItRotates() {
    #expect(next(.code(code), .login) == .code(code))
    let fresh = LinkCode.payload("2@next")
    #expect(next(.code(code), .login, code: fresh) == .code(fresh))
    #expect(next(.linking, .login, code: fresh) == .code(fresh), "a failed scan shows a new code")
  }

  @Test func failures() {
    #expect(next(.loadingCode, .unsupported) == .failed(.unsupported))
    #expect(next(.loadingCode, .login, polls: LinkPhase.codeTimeoutPolls) == .failed(.noCode))
    #expect(next(.loadingCode, .loading, polls: LinkPhase.codeTimeoutPolls) == .failed(.noCode))
    #expect(next(.code(code), .login, password: true) == .failed(.needsPassword))
    #expect(LinkPhase.success.isFinished && LinkPhase.failed(.noCode).isFinished && !LinkPhase.linking.isFinished)
  }
}

// MARK: - QR

@MainActor
struct ReplyQRTests {
  @Test func drawnCodeIsDecodedAndReEncodedCrisply() throws {
    let text = "2@AbC123,xyz==,key=="
    let image = try #require(ReplyQRImage.encode(text))
    let big = NSImage(size: NSSize(width: 264, height: 264), flipped: false) { rect in
      NSGraphicsContext.current?.imageInterpolation = .none
      NSColor.white.setFill()
      rect.fill()
      image.draw(in: rect.insetBy(dx: 16, dy: 16))
      return true
    }
    let tiff = try #require(big.tiffRepresentation)
    let png = try #require(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
    #expect(ReplyQRImage.decode(png) == text)
    let crisp = try #require(ReplyQRImage.image(for: .image(png)))
    let direct = try #require(ReplyQRImage.encode(text))
    #expect(crisp.size == direct.size, "the drawn code is replaced by a re-encoded one")
    #expect(crisp.size.width >= 400 && crisp.size.width <= ReplyQRImage.targetPixels, "whole pixels per module")
    let crispTIFF = try #require(crisp.tiffRepresentation)
    let reencoded = try #require(NSBitmapImageRep(data: crispTIFF)?.representation(using: .png, properties: [:]))
    #expect(ReplyQRImage.decode(reencoded) == text)
  }

  @Test func parsesTheQRScriptJSON() {
    let png = Data([0x89, 0x50, 0x4E, 0x47])
    let url = "data:image/png;base64," + png.base64EncodedString()
    let withImage = WebMessengerSession.snapshot(status: .login, qrJSON: #"{"image":"\#(url)"}"#)
    #expect(withImage.code == .image(png))
    #expect(WebMessengerSession.snapshot(status: .login, qrJSON: #"{"payload":"2@x"}"#).code == .payload("2@x"))
    #expect(WebMessengerSession.snapshot(status: .login, qrJSON: "{}").code == nil)
    #expect(WebMessengerSession.snapshot(status: .login, qrJSON: "garbage").code == nil)
    #expect(WebMessengerSession.snapshot(status: .login, qrJSON: #"{"needsPassword":true}"#).needsPassword)
    #expect(ReplyQRImage.data(fromDataURL: "javascript:alert(1)") == nil)
  }
}

// MARK: - Coordinator

@MainActor
struct ReplyCoordinatorTests {
  private let wa = NotificationContent(bundleID: "net.whatsapp.WhatsApp", appName: "WhatsApp", title: "Anna", body: "hi")

  private func make(_ session: FakeLinkSession, messages: RecordingTransport? = nil) -> (ReplyCoordinator, Void) {
    let coordinator = ReplyCoordinator(messages: messages ?? RecordingTransport(), sessions: { $0 == session.channel ? session : nil }) { session in
      let linker = ReplyLinker(session: session)
      linker.pollInterval = .milliseconds(1)
      linker.successHold = .milliseconds(1)
      return linker
    }
    return (coordinator, ())
  }

  @Test func unlinkedChannelOpensTheLinkPanelAndKeepsTheDraft() async {
    let session = FakeLinkSession()
    session.snapshots = [LinkSnapshot(status: .login, code: code)]
    let (c, _) = make(session)
    c.drafts[wa.id] = "On my way"
    c.send("On my way", to: wa)
    await waitFor { c.linker != nil }
    #expect(c.linkingItemID == wa.id)
    #expect(c.drafts[wa.id] == "On my way")
    #expect(c.holdsIslandOpen)
    #expect(session.sent.isEmpty)
    await waitFor { c.linker?.phase == .code(code) }
    #expect(c.linker?.phase == .code(code))
    c.cancelLink()
  }

  @Test func scanningSendsThePendingDraftAutomatically() async {
    let session = FakeLinkSession()
    session.snapshots = [LinkSnapshot(status: .login, code: code), LinkSnapshot(status: .loading),
                         LinkSnapshot(status: .connected)]
    var sent: [UUID] = []
    let (c, _) = make(session)
    c.onSent = { sent.append($0) }
    c.send("On my way", to: wa)
    await waitFor { c.state == .sent }
    #expect(c.state == .sent)
    #expect(c.linker == nil && !c.holdsIslandOpen)
    #expect(session.sent.map(\.text) == ["On my way"])
    #expect(session.sent.first?.afterLink == true)
    #expect(session.sent.first?.names == ["Anna"])
    #expect(c.drafts[wa.id] == nil)
    #expect(sent == [wa.id])
  }

  @Test func cancelKeepsTheDraftAndSendsNothing() async {
    let session = FakeLinkSession()
    session.snapshots = [LinkSnapshot(status: .login, code: code)]
    let (c, _) = make(session)
    c.drafts[wa.id] = "Later"
    c.send("Later", to: wa)
    await waitFor { c.linker != nil }
    c.cancelLink()
    #expect(c.linker == nil && c.state == .idle && !c.holdsIslandOpen)
    #expect(c.drafts[wa.id] == "Later")
    try? await Task.sleep(for: .milliseconds(30))
    #expect(session.sent.isEmpty)
  }

  @Test func loadingLinkedSessionShowsConnectingThenSends() async {
    let session = FakeLinkSession()
    session.isLinked = true
    session.readyDelay = .milliseconds(80)
    let (c, _) = make(session)
    c.send("hi", to: wa)
    await waitFor { c.state == .connecting }
    #expect(c.state == .connecting && c.holdsIslandOpen)
    await waitFor { c.state == .sent }
    #expect(session.sent.map(\.text) == ["hi"])
    #expect(session.sent.first?.afterLink == false)
  }

  @Test func loggedOutSessionReopensTheLinkPanel() async {
    let session = FakeLinkSession()
    session.isLinked = true
    session.readiness = [.needsLogin]
    session.snapshots = [LinkSnapshot(status: .login, code: code)]
    let (c, _) = make(session)
    c.drafts[wa.id] = "hi"
    c.send("hi", to: wa)
    await waitFor { c.linker != nil }
    #expect(c.linker != nil && c.drafts[wa.id] == "hi" && session.sent.isEmpty)
    c.cancelLink()
  }

  @Test func sessionThatTurnsOutSignedOutMidSendRelinks() async {
    let session = FakeLinkSession()
    session.isLinked = true
    session.isReady = true
    session.sendResults = [.failure(.notConnected(.whatsApp))]
    session.snapshots = [LinkSnapshot(status: .login, code: code)]
    let (c, _) = make(session)
    c.send("hi", to: wa)
    await waitFor { c.linker != nil }
    #expect(c.linker != nil)
    c.cancelLink()
  }

  @Test func neverReadyFailsWithAMessage() async {
    let session = FakeLinkSession()
    session.isLinked = true
    session.readiness = [.notReady]
    let (c, _) = make(session)
    c.send("hi", to: wa)
    await waitFor { if case .failed = c.state { return true } else { return false } }
    #expect(c.state == .failed(ReplyError.notReady(.whatsApp).message))
  }

  @Test func messagesGoesStraightThroughItsTransport() async {
    let messages = RecordingTransport()
    let (c, _) = make(FakeLinkSession(), messages: messages)
    let item = NotificationContent(bundleID: NotificationApps.messages, appName: "Messages", title: "Mo")
    c.send("yo", to: item)
    await waitFor { c.state == .sent }
    #expect(messages.sent.map(\.0) == ["yo"])
  }

  @Test func busyOrLinkingIgnoresAnotherSend() async {
    let session = FakeLinkSession()
    session.snapshots = [LinkSnapshot(status: .login, code: code)]
    let (c, _) = make(session)
    c.send("one", to: wa)
    await waitFor { c.linker != nil }
    c.send("two", to: wa)
    #expect(c.pending?.text == "one")
    c.cancelLink()
  }

  @Test func closingTheCardDropsItsDraftAndSuspendsUnlinkedPages() async {
    let session = FakeLinkSession()
    session.snapshots = [LinkSnapshot(status: .login, code: code)]
    let (c, _) = make(session)
    c.drafts[wa.id] = "x"
    c.send("x", to: wa)
    await waitFor { c.linker != nil }
    c.cardClosed(wa.id)
    #expect(c.linker == nil && c.drafts[wa.id] == nil && session.suspends == 1)
  }

  @Test func holdPolicy() {
    #expect(ReplyHoldPolicy.holdsIslandOpen(state: .idle, linking: true))
    #expect(ReplyHoldPolicy.holdsIslandOpen(state: .connecting, linking: false))
    #expect(ReplyHoldPolicy.holdsIslandOpen(state: .sending, linking: false))
    #expect(!ReplyHoldPolicy.holdsIslandOpen(state: .idle, linking: false))
    #expect(!ReplyHoldPolicy.holdsIslandOpen(state: .sent, linking: false))
    #expect(!ReplyHoldPolicy.holdsIslandOpen(state: .failed("x"), linking: false))
    #expect(NotificationCardMetrics.bodyHeight(supportsReply: false, linking: false) == 92)
    #expect(NotificationCardMetrics.bodyHeight(supportsReply: true, linking: false) == 136)
    #expect(NotificationCardMetrics.bodyHeight(supportsReply: true, linking: true) > 136 + 150)
  }
}

// MARK: - Linker and session health

@MainActor
struct ReplyLinkerTests {
  @Test func retryReloadsAndStartsOver() async {
    let session = FakeLinkSession()
    session.snapshots = [LinkSnapshot(status: .unsupported)]
    let linker = ReplyLinker(session: session)
    linker.pollInterval = .milliseconds(1)
    linker.start()
    await waitFor { linker.phase == .failed(.unsupported) }
    #expect(linker.phase == .failed(.unsupported) && !linker.isRunning)
    session.snapshots = [LinkSnapshot(status: .login, code: code)]
    linker.retry()
    #expect(session.reloads == 1)
    await waitFor { linker.phase == .code(code) }
    #expect(linker.phase == .code(code))
    linker.stop()
  }

  @Test func alreadyLinkedShowsSuccessWithoutPolling() {
    let session = FakeLinkSession()
    session.isLinked = true
    session.isReady = true
    let linker = ReplyLinker(session: session)
    linker.start()
    #expect(linker.phase == .success && !linker.isRunning)
  }

  @Test func sessionWaitsUntilReadyAndDetectsLogout() async {
    let page = FakeWebPage()
    page.answers["whatsapp.status"] = [.string("loading"), .string("loading"), .string("connected")]
    let link = MemoryLink()
    link.linked = true
    let session = WebMessengerSession(profile: .whatsApp, pacing: fastPacing, link: link.link) { _ in page }
    session.pollsAutomatically = false
    #expect(await session.waitUntilReady(timeout: .seconds(2)) == .ready)
    page.answers["whatsapp.status"] = [.string("login")]
    #expect(await session.linkSnapshot().status == .login)
    #expect(link.linked, "one login read is not enough")
    _ = await session.linkSnapshot()
    #expect(!link.linked && session.state == .needsLogin)
  }

  @Test func suspendOnlyDropsUnlinkedPages() {
    let page = FakeWebPage()
    let link = MemoryLink()
    let session = WebMessengerSession(profile: .whatsApp, pacing: fastPacing, link: link.link) { _ in page }
    session.pollsAutomatically = false
    link.linked = true
    session.activate()
    session.suspend()
    #expect(session.driver != nil)
    link.linked = false
    session.suspend()
    #expect(session.driver == nil && page.tornDown && session.state == .off)
  }
}

// MARK: - Onboarding offer

@MainActor
struct ReplyLinkOfferTests {
  @Test func offeredOnlyWhenInstalledNotLinkedAndNotYetOffered() {
    let installed: (ReplyChannel) -> Bool = { $0 == .whatsApp }
    #expect(ReplyLinkOffer.channels(installed: installed, linked: { _ in false }, offered: false) == [.whatsApp])
    #expect(ReplyLinkOffer.channels(installed: installed, linked: { _ in true }, offered: false).isEmpty)
    #expect(ReplyLinkOffer.channels(installed: installed, linked: { _ in false }, offered: true).isEmpty)
    #expect(ReplyLinkOffer.channels(installed: { _ in false }, linked: { _ in false }, offered: false).isEmpty)
    #expect(ReplyLinkOffer.channels(installed: { _ in true }, linked: { _ in false }, offered: false) == [.whatsApp, .telegram])
  }

  @Test func tourIncludesTheReplyPageOnlyWhenOffering() {
    #expect(!OnboardingPage.tour(offeringReplies: false).contains(.replies))
    let tour = OnboardingPage.tour(offeringReplies: true)
    #expect(tour.firstIndex(of: .replies) == tour.firstIndex(of: .live).map { $0 + 1 })
    let flow = OnboardingFlow(page: .welcome, pages: OnboardingPage.tour(offeringReplies: false))
    flow.go(to: flow.pages.firstIndex(of: .live)!)
    flow.step(1)
    #expect(flow.page == .lockScreen)
  }

  @Test func showingThePageMarksItOffered() throws {
    let defaults = try #require(UserDefaults(suiteName: "reply-offer-\(UUID().uuidString)"))
    #expect(!defaults.bool(forKey: ReplyLinkOffer.offeredKey))
    let model = TourReplyModel(previewPhase: .loadingCode, defaults: defaults)
    model.appear()
    #expect(defaults.bool(forKey: ReplyLinkOffer.offeredKey))
    #expect(model.linker == nil, "a preview never loads the real site")
    model.select(model.channel == .whatsApp ? .telegram : .whatsApp)
    #expect(model.linker == nil)
  }
}
