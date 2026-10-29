// WhatsAppWebProfile.swift
// Brim
//
// Page scripts for web.whatsapp.com. WhatsApp ships `data-testid`s only some of the time, so each
// lookup tries stable ids first, then roles and structure (#pane-side, #main, footer).
// The UI language is pinned to English at document start: the login/unsupported checks read
// English text, while chat names come from `title` attributes and are never translated.

import Foundation

extension WebMessengerProfile {
  static let whatsApp = WebMessengerProfile(
    channel: .whatsApp,
    home: URL(string: "https://web.whatsapp.com/")!,
    dataStoreID: UUID(uuidString: "7B1F3C52-9E0A-4D7B-8C21-5A3E6F0D9B41")!,
    userAgent: safariUserAgent,
    documentStart: WhatsAppWebScripts.pinEnglish,
    status: WebScript("whatsapp.status", WhatsAppWebScripts.status),
    openChat: WebScript("whatsapp.openChat", WhatsAppWebScripts.openChat),
    search: WebScript("whatsapp.search", WhatsAppWebScripts.search),
    activeChat: WebScript("whatsapp.activeChat", WhatsAppWebScripts.activeChat),
    compose: WebScript("whatsapp.compose", WhatsAppWebScripts.compose),
    send: WebScript("whatsapp.send", WhatsAppWebScripts.send),
    confirm: WebScript("whatsapp.confirm", WhatsAppWebScripts.confirm),
    closeChat: WebScript("whatsapp.closeChat", "pressEscape();"),
    qrCode: WebScript("whatsapp.qrCode", WhatsAppWebScripts.qrCode))
}

enum WhatsAppWebScripts {
  static let pinEnglish = #"""
  (() => {
    try { Object.defineProperty(navigator, "language", { get: () => "en-US" }); } catch (_) {}
    try { Object.defineProperty(navigator, "languages", { get: () => ["en-US", "en"] }); } catch (_) {}
  })();
  """#

  /// Shared lookups, prefixed to the scripts that need them.
  static let lookups = #"""
  const chatPane = () => document.querySelector("#pane-side") || document.querySelector("#side")
    || document.querySelector("[data-testid='chat-list']") || document.querySelector("[aria-label='Chat list']");
  const chatRows = () => {
    const root = chatPane();
    if (!root) { return []; }
    const rows = Array.from(root.querySelectorAll("[data-testid='cell-frame-container'], [role='listitem'], [role='row']"));
    return rows.map((row) => {
      const label = row.querySelector("[data-testid='cell-frame-title'] span[title], span[title], [data-testid='cell-frame-title'] span[dir='auto']");
      return { el: row, title: readText(label) };
    }).filter((item) => item.title !== "");
  };
  const composer = () => document.querySelector("footer div[contenteditable='true'][data-tab]")
    || document.querySelector("footer div[contenteditable='true']")
    || document.querySelector("#main div[contenteditable='true'][role='textbox']");
  const outgoing = () => Array.from(document.querySelectorAll("#main .message-out, #main [data-testid='msg-container'].message-out"));
  """#

  /// The code lives in a canvas under `[data-ref]`. After a few unscanned rotations WhatsApp
  /// covers it with a "click to reload" button, which is pressed here so a fresh code appears.
  static let qrCode = #"""
  const host = document.querySelector("[data-ref]");
  const reload = host ? host.querySelector("button, [role='button']") : null;
  if (reload) { fire(reload); return JSON.stringify({}); }
  const canvas = document.querySelector("[data-ref] canvas, canvas[aria-label*='Scan'], canvas[aria-label*='scan']");
  let image = null;
  if (canvas && canvas.width > 0) { try { image = canvas.toDataURL("image/png"); } catch (_) {} }
  return JSON.stringify({ image });
  """#

  static let status = #"""
  const has = (s) => !!document.querySelector(s);
  const qr = has("canvas[aria-label*='Scan'], canvas[aria-label*='scan'], [data-ref] canvas, canvas[data-ref], [data-testid='qrcode']");
  const chats = has("#pane-side, #side, [data-testid='chat-list'], [aria-label='Chat list']");
  if (chats && !qr) { return "connected"; }
  if (qr) { return "login"; }
  const text = (document.body ? document.body.innerText : "").toLowerCase();
  if (text.includes("browser is not supported") || text.includes("works with safari") || text.includes("update your browser")) { return "unsupported"; }
  if (text.includes("link with phone number") || text.includes("scan the qr code") || text.includes("log in with phone number")) { return "login"; }
  return "loading";
  """#

  static let openChat = lookups + #"""
  const header = document.querySelector("#main header");
  if (header) {
    const labels = Array.from(header.querySelectorAll("[title], span[dir='auto']"));
    if (labels.some((el) => nameMatches(readText(el)))) { return "open"; }
  }
  const row = pickByName(chatRows());
  if (!row) { return ""; }
  fire(row);
  return "clicked";
  """#

  static let search = #"""
  const box = document.querySelector("#side input[role='textbox'], #side input[type='text'], input[aria-label*='Search']")
    || document.querySelector("div[contenteditable='true'][data-tab='3']")
    || document.querySelector("#side div[contenteditable='true']");
  if (!box || nameList.length === 0) { return ""; }
  return (await typeInto(box, nameList[0])) ? "typed" : "";
  """#

  static let activeChat = #"""
  const header = document.querySelector("#main header");
  if (!header) { return false; }
  return Array.from(header.querySelectorAll("[title], span[dir='auto']")).some((el) => nameMatches(readText(el)));
  """#

  static let compose = lookups + #"""
  const box = composer();
  if (!box) { return "nocomposer"; }
  return (await typeInto(box, String(text))) ? "ok" : "empty";
  """#

  static let send = lookups + #"""
  const before = outgoing().length;
  const footer = document.querySelector("footer") || document.querySelector("#main") || document;
  const icon = footer.querySelector("span[data-icon='send'], span[data-icon='wds-ic-send-filled'], span[data-icon='send-light']");
  const button = footer.querySelector("[data-testid='send'], button[aria-label='Send']") || (icon && icon.closest("button, [role='button']"));
  if (button) { fire(button); return before; }
  const box = composer();
  if (!box) { return -1; }
  box.focus();
  box.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", code: "Enter", keyCode: 13, which: 13, bubbles: true, cancelable: true }));
  return before;
  """#

  static let confirm = lookups + #"""
  const box = composer();
  if (box && editorText(box) !== "") { return "pending"; }
  const list = outgoing();
  if (list.length > Number(before)) { return "sent"; }
  const last = list[list.length - 1];
  const sample = bare(String(text)).slice(0, 24);
  if (last && sample !== "" && bare(readText(last)).includes(sample)) { return "sent"; }
  return list.length === 0 ? "sent" : "pending";
  """#
}
