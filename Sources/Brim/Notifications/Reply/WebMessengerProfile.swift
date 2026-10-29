// WebMessengerProfile.swift
// Brim
//
// Describes one web messenger (WhatsApp Web, Telegram Web) for the hidden reply session: where
// it lives, its private data store and the page scripts that read login state, open a chat,
// type, send and confirm.
//
// Script sources are fixed constants. They are run with `callAsyncJavaScript(_:arguments:)`, so
// the chat names and reply text reach the page as real JavaScript values (`names`, `text`,
// `before`), never as source code. Nothing a contact or the user types can change what runs.

import Foundation

struct WebScript: Equatable, Sendable {
  let name: String
  let source: String

  /// Every script gets the shared helpers in front of its own body.
  init(_ name: String, _ body: String) {
    self.name = name
    self.source = WebScriptPrelude.source + "\n" + body
  }
}

/// Results the page scripts return, as plain strings so they cross the bridge unchanged.
enum WebPageStatus: String, Sendable {
  case connected, login, loading, unsupported
}

struct WebMessengerProfile: Sendable {
  let channel: ReplyChannel
  let home: URL
  /// Identifier of this messenger's own persistent WKWebsiteDataStore. Nothing else uses it.
  let dataStoreID: UUID
  let userAgent: String
  /// Runs in the page's world before its own code (e.g. to pin the UI language).
  let documentStart: String?
  /// -> WebPageStatus raw value.
  let status: WebScript
  /// (names) -> "open" if that chat is already open, "clicked" when a row was pressed, "" otherwise.
  let openChat: WebScript
  /// (names) -> "typed" once the name is in the chat search box, "" when there is no search box.
  let search: WebScript
  /// (names) -> true when the open conversation's header matches one of the names.
  let activeChat: WebScript
  /// (text) -> "ok" | "nocomposer" | "empty".
  let compose: WebScript
  /// () -> number of outgoing messages before pressing send, or -1 when there is no send control.
  let send: WebScript
  /// (text, before) -> "sent" | "pending".
  let confirm: WebScript
  /// () -> closes the conversation so new messages there are not marked read in the background.
  let closeChat: WebScript
  /// () -> JSON {payload?, image? (data URL), needsPassword?} for the login QR code.
  let qrCode: WebScript

  static func profile(for channel: ReplyChannel) -> WebMessengerProfile? {
    switch channel {
    case .messages: return nil
    case .whatsApp: return .whatsApp
    case .telegram: return .telegram
    }
  }

  /// A current Safari user agent. WKWebView's default omits "Version/… Safari/…", and both sites
  /// then refuse the browser.
  static let safariUserAgent =
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Safari/605.1.15"
}

/// Helpers shared by every page script: name folding, title reading, synthetic clicks, typing.
enum WebScriptPrelude {
  static let source = #"""
  const fold = (s) => String(s || "").normalize("NFC")
    .replace(/[​-‏⁠﻿︎️]/g, "")
    .replace(/^~\s*/, "").replace(/\s+/g, " ").trim().toLowerCase();
  const bare = (s) => fold(s).replace(/[^\p{L}\p{M}\p{N} ]/gu, "").replace(/ +/g, " ").trim();
  const readText = (el) => {
    if (!el) { return ""; }
    const attr = el.getAttribute && el.getAttribute("title");
    if (attr) { return attr; }
    const walk = (n) => {
      if (n.nodeType === 3) { return n.nodeValue || ""; }
      if (n.nodeName === "IMG") { return n.getAttribute("alt") || ""; }
      let out = "";
      for (const kid of Array.from(n.childNodes || [])) { out += walk(kid); }
      return out;
    };
    return walk(el);
  };
  const nameList = (typeof names !== "undefined" && Array.isArray(names)) ? names.map(String) : [];
  const nameMatches = (title) => nameList.some((n) => fold(n) === fold(title) || (bare(n) !== "" && bare(n) === bare(title)));
  const pickByName = (items) => {
    for (const n of nameList) {
      const hit = items.find((i) => fold(i.title) === fold(n));
      if (hit) { return hit.el; }
    }
    for (const n of nameList) {
      const key = bare(n);
      if (!key) { continue; }
      const hits = items.filter((i) => bare(i.title) === key);
      if (hits.length === 1) { return hits[0].el; }
    }
    return null;
  };
  const fire = (el) => {
    const opts = { bubbles: true, cancelable: true, view: window };
    try { el.dispatchEvent(new PointerEvent("pointerdown", opts)); } catch (_) {}
    el.dispatchEvent(new MouseEvent("mousedown", opts));
    try { el.dispatchEvent(new PointerEvent("pointerup", opts)); } catch (_) {}
    el.dispatchEvent(new MouseEvent("mouseup", opts));
    el.dispatchEvent(new MouseEvent("click", opts));
  };
  const pause = (ms) => new Promise((done) => setTimeout(done, ms));
  const selectContents = (el) => {
    el.focus();
    const range = document.createRange();
    range.selectNodeContents(el);
    const sel = window.getSelection();
    sel.removeAllRanges();
    sel.addRange(range);
  };
  const editorText = (el) => fold(readText(el));
  /// Types like a user would: editors such as WhatsApp's listen for beforeinput/input, not value.
  const typeInto = async (el, value) => {
    if (el.tagName === "INPUT" || el.tagName === "TEXTAREA") {
      el.focus();
      const proto = el.tagName === "INPUT" ? HTMLInputElement.prototype : HTMLTextAreaElement.prototype;
      Object.getOwnPropertyDescriptor(proto, "value").set.call(el, value);
      el.dispatchEvent(new InputEvent("input", { bubbles: true, inputType: "insertText", data: value }));
      return el.value !== "";
    }
    selectContents(el);
    try { document.execCommand("insertText", false, value); } catch (_) {}
    await pause(120);
    if (editorText(el) !== "") { return true; }
    selectContents(el);
    try {
      const data = new DataTransfer();
      data.setData("text/plain", value);
      el.dispatchEvent(new ClipboardEvent("paste", { clipboardData: data, bubbles: true, cancelable: true }));
    } catch (_) {}
    await pause(160);
    if (editorText(el) !== "") { return true; }
    el.dispatchEvent(new InputEvent("beforeinput", { bubbles: true, cancelable: true, inputType: "insertText", data: value }));
    await pause(160);
    return editorText(el) !== "";
  };
  const pressEscape = () => {
    const target = document.activeElement || document.body;
    for (const type of ["keydown", "keyup"]) {
      target.dispatchEvent(new KeyboardEvent(type, { key: "Escape", code: "Escape", keyCode: 27, which: 27, bubbles: true }));
    }
    if (document.activeElement && document.activeElement.blur) { document.activeElement.blur(); }
  };
  """#
}
