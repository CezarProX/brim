import Foundation
import Testing
import WebKit

@testable import Brim

/// Runs the real page scripts in a real WKWebView against small fixture pages that mimic the
/// WhatsApp Web and Telegram Web DOM. The fixture editors only accept text through input events
/// (they ignore direct value writes), so a pass means the typing path really works.
@MainActor
@Suite(.serialized)
struct WebMessengerPageScriptTests {
  private func page(_ html: String, profile: WebMessengerProfile) async throws -> WKWebPageDriver {
    let driver = WKWebPageDriver(profile: profile, dataStore: .nonPersistent())
    driver.loadHTML(html, baseURL: nil)
    let ready = WebScript("test.ready", "return document.readyState === 'complete' && !!document.getElementById('fixture');")
    for _ in 0..<100 {
      if (try? await driver.run(ready, arguments: [:]))?.bool == true { return driver }
      try await Task.sleep(for: .milliseconds(50))
    }
    Issue.record("fixture page never loaded")
    return driver
  }

  private var pacing: ReplyPacing {
    ReplyPacing(readyAttempts: 5, chatAttempts: 10, confirmAttempts: 10, interval: .milliseconds(60), scriptTimeout: .seconds(5))
  }

  private func evaluate(_ driver: WKWebPageDriver, _ body: String) async throws -> WebValue {
    try await driver.run(WebScript("test.eval", body), arguments: [:])
  }

  @Test func whatsAppReplyTypesSendsAndConfirms() async throws {
    let driver = try await page(WebFixtures.whatsApp, profile: .whatsApp)
    defer { driver.tearDown() }
    let hostile = #"Hi "Anna"</script><script>window.__pwned=1</script> ${x} `y` 😀"#
    let sender = WebReplySender(driver: driver, profile: .whatsApp, pacing: pacing)
    try await sender.send(text: hostile, names: ["Family 👪", "Anna Kowalski"])
    #expect(try await evaluate(driver, "return document.querySelector('#main header span').getAttribute('title');")
      == .string("Family 👪"))
    #expect(try await evaluate(driver, "return document.querySelector('.message-out:last-child span').textContent;")
      == .string(hostile))
    #expect(try await evaluate(driver, "return String(typeof window.__pwned);") == .string("undefined"))
    #expect(try await evaluate(driver, "return document.body.dataset.closed || '';") == .string("yes"))
  }

  @Test func whatsAppFindsUnlistedChatThroughSearch() async throws {
    let driver = try await page(WebFixtures.whatsApp, profile: .whatsApp)
    defer { driver.tearDown() }
    try await WebReplySender(driver: driver, profile: .whatsApp, pacing: pacing).send(text: "ok", names: ["Zed"])
    #expect(try await evaluate(driver, "return document.querySelector('#main header span').getAttribute('title');")
      == .string("Zed"))
  }

  @Test func whatsAppBareNameMatchIgnoresEmojiAndTilde() async throws {
    let driver = try await page(WebFixtures.whatsApp, profile: .whatsApp)
    defer { driver.tearDown() }
    try await WebReplySender(driver: driver, profile: .whatsApp, pacing: pacing).openChat(names: ["~ family"])
    #expect(try await evaluate(driver, "return document.querySelector('#main header span').getAttribute('title');")
      == .string("Family 👪"))
  }

  @Test func whatsAppStatusDetectsLoginAndChats() async throws {
    let login = try await page(WebFixtures.whatsAppLogin, profile: .whatsApp)
    defer { login.tearDown() }
    #expect(try await login.run(WebMessengerProfile.whatsApp.status, arguments: [:]) == .string("login"))
    let chats = try await page(WebFixtures.whatsApp, profile: .whatsApp)
    defer { chats.tearDown() }
    #expect(try await chats.run(WebMessengerProfile.whatsApp.status, arguments: [:]) == .string("connected"))
  }

  @Test func unknownChatIsReportedNotGuessed() async throws {
    let driver = try await page(WebFixtures.whatsApp, profile: .whatsApp)
    defer { driver.tearDown() }
    await #expect(throws: ReplyError.chatNotFound) {
      try await WebReplySender(driver: driver, profile: .whatsApp, pacing: pacing).openChat(names: ["Nobody Here"])
    }
  }

  @Test func telegramReplyTypesSendsAndConfirms() async throws {
    let driver = try await page(WebFixtures.telegram, profile: .telegram)
    defer { driver.tearDown() }
    #expect(try await driver.run(WebMessengerProfile.telegram.status, arguments: [:]) == .string("connected"))
    try await WebReplySender(driver: driver, profile: .telegram, pacing: pacing).send(text: "See you at 8", names: ["Maya"])
    #expect(try await evaluate(driver, "return document.querySelector('.bubble.is-out:last-child .message').textContent;")
      == .string("See you at 8"))
  }
}

/// Minimal look-alikes of the two sites' DOM. Their editors only take input-event text.
enum WebFixtures {
  static let whatsApp = #"""
  <html><body><div id="fixture"></div>
  <div id="side"><div><input type="text" aria-label="Search or start a new chat"></div>
    <div id="pane-side"><div role="grid">
      <div role="listitem" data-name="Anna Kowalski"><span dir="auto" title="Anna Kowalski">Anna Kowalski</span></div>
      <div role="listitem" data-name="Family 👪"><span dir="auto" title="Family 👪">Family 👪</span></div>
    </div></div></div>
  <div id="main"><header><span dir="auto" title=""></span></header><div id="msgs"></div>
    <footer><div contenteditable="true" role="textbox" data-tab="10"></div>
      <button aria-label="Send"><span data-icon="send"></span></button></footer></div>
  <script>
    const open = (name) => { const h = document.querySelector('#main header span'); h.setAttribute('title', name); h.textContent = name; };
    const bind = (row) => row.addEventListener('click', () => open(row.dataset.name));
    document.querySelectorAll('[role=listitem]').forEach(bind);
    const search = document.querySelector('#side input');
    search.addEventListener('input', () => {
      if (search.value !== 'Zed' || document.querySelector('[data-name=Zed]')) { return; }
      const row = document.createElement('div');
      row.setAttribute('role', 'listitem'); row.dataset.name = 'Zed';
      row.innerHTML = '<span dir="auto" title="Zed">Zed</span>';
      bind(row); document.querySelector('#pane-side [role=grid]').appendChild(row);
    });
    const editor = document.querySelector('footer [contenteditable]');
    let typed = '';
    editor.addEventListener('beforeinput', (e) => { if (e.inputType === 'insertText') { typed = e.data; } });
    editor.addEventListener('input', () => { editor.dataset.accepted = typed; });
    document.querySelector('footer button').addEventListener('click', () => {
      const text = editor.dataset.accepted || '';
      if (!text) { return; }
      const bubble = document.createElement('div'); bubble.className = 'message-out';
      const span = document.createElement('span'); span.textContent = text; bubble.appendChild(span);
      document.getElementById('msgs').appendChild(bubble);
      editor.textContent = ''; editor.dataset.accepted = '';
    });
    document.addEventListener('keydown', (e) => { if (e.key === 'Escape') { document.body.dataset.closed = 'yes'; } }, true);
  </script></body></html>
  """#

  static let whatsAppLogin = #"""
  <html><body><div id="fixture"></div><div data-ref="2@abc"><canvas aria-label="Scan this QR code to link a device!" width="264" height="264"></canvas></div>
  <p>Steps to log in</p></body></html>
  """#

  static let telegram = #"""
  <html><body><div id="fixture"></div>
  <div id="column-left"><div class="input-search"><input class="input-search-input"></div>
    <ul class="chatlist"><a class="chatlist-chat" data-peer-id="7"><span class="peer-title">Maya</span></a></ul></div>
  <div id="column-center"><div class="chat tabs-tab active">
    <div class="chat-info"><span class="peer-title"></span></div><div class="bubbles"></div>
    <div class="input-message-input input-field-input-fake" contenteditable="true"></div>
    <div class="input-message-input" contenteditable="true"></div>
    <button class="btn-send send"></button></div></div>
  <script>
    document.querySelector('.chatlist-chat').addEventListener('mousedown', () => { document.querySelector('.chat-info .peer-title').textContent = 'Maya'; });
    const editor = document.querySelector('.input-message-input:not(.input-field-input-fake)');
    document.querySelector('.btn-send').addEventListener('click', () => {
      const text = editor.textContent; if (!text) { return; }
      const b = document.createElement('div'); b.className = 'bubble is-out';
      const m = document.createElement('div'); m.className = 'message'; m.textContent = text; b.appendChild(m);
      document.querySelector('.bubbles').appendChild(b); editor.textContent = '';
    });
  </script></body></html>
  """#
}
