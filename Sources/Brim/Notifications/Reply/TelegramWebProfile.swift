// TelegramWebProfile.swift
// Brim
//
// Page scripts for Telegram Web (the "K" client at web.telegram.org/k/). Telegram for macOS has
// no AppleScript dictionary, and its tg:// links need a @username or phone number, which a
// notification never carries, so replies go through a linked Telegram Web session instead.

import Foundation

extension WebMessengerProfile {
  static let telegram = WebMessengerProfile(
    channel: .telegram,
    home: URL(string: "https://web.telegram.org/k/")!,
    dataStoreID: UUID(uuidString: "C4D2A7E9-1B36-4F58-9A0C-3E7B5D21F864")!,
    userAgent: safariUserAgent,
    documentStart: nil,
    status: WebScript("telegram.status", TelegramWebScripts.status),
    openChat: WebScript("telegram.openChat", TelegramWebScripts.openChat),
    search: WebScript("telegram.search", TelegramWebScripts.search),
    activeChat: WebScript("telegram.activeChat", TelegramWebScripts.activeChat),
    compose: WebScript("telegram.compose", TelegramWebScripts.compose),
    send: WebScript("telegram.send", TelegramWebScripts.send),
    confirm: WebScript("telegram.confirm", TelegramWebScripts.confirm),
    closeChat: WebScript("telegram.closeChat", "pressEscape();"),
    qrCode: WebScript("telegram.qrCode", TelegramWebScripts.qrCode))
}

enum TelegramWebScripts {
  static let lookups = #"""
  const activeChat = () => document.querySelector("#column-center .chat.active")
    || document.querySelector("#column-center .chat.tabs-tab.active") || document.querySelector("#column-center");
  const chatRows = () => Array.from(document.querySelectorAll("#column-left a.chatlist-chat, #column-left [data-peer-id].row"))
    .map((row) => ({ el: row, title: readText(row.querySelector(".peer-title, .user-title")) }))
    .filter((item) => item.title !== "");
  const composer = () => {
    const scope = activeChat();
    return scope ? scope.querySelector(".input-message-input[contenteditable='true']:not(.input-field-input-fake)") : null;
  };
  const outgoing = () => {
    const scope = activeChat();
    return scope ? Array.from(scope.querySelectorAll(".bubble.is-out")) : [];
  };
  """#

  /// The QR is a canvas or an SVG on the sign-in page; an SVG is rasterised first. After the
  /// scan, an account with a cloud password shows the password page instead.
  static let qrCode = #"""
  const shown = (el) => !!el && el.getClientRects().length > 0;
  const password = Array.from(document.querySelectorAll(".page-password, [class*='pagePassword'], #auth-pages input[type='password']")).some(shown);
  if (password) { return JSON.stringify({ needsPassword: true }); }
  const scope = Array.from(document.querySelectorAll(".page-signQR, [class*='pageSignQR'], .qr-container")).filter(shown);
  const all = (tag) => scope.flatMap((el) => Array.from(el.querySelectorAll(tag))).filter(shown);
  const canvas = all("canvas").filter((c) => c.width >= 80 && Math.abs(c.width - c.height) <= 4)
    .sort((a, b) => b.width - a.width)[0];
  if (canvas) { try { return JSON.stringify({ image: canvas.toDataURL("image/png") }); } catch (_) {} }
  const svg = all("svg").find((el) => el.getBoundingClientRect().width >= 80);
  if (!svg) { return JSON.stringify({}); }
  const markup = new XMLSerializer().serializeToString(svg);
  const img = new Image();
  img.src = "data:image/svg+xml;charset=utf-8," + encodeURIComponent(markup);
  try { await img.decode(); } catch (_) { return JSON.stringify({}); }
  const side = 512;
  const out = document.createElement("canvas");
  out.width = side; out.height = side;
  const ctx = out.getContext("2d");
  ctx.fillStyle = "#fff"; ctx.fillRect(0, 0, side, side);
  ctx.drawImage(img, 0, 0, side, side);
  return JSON.stringify({ image: out.toDataURL("image/png") });
  """#

  static let status = #"""
  const body = document.body;
  if (!body) { return "loading"; }
  const shown = (el) => !!el && el.getClientRects().length > 0;
  const auth = body.classList.contains("has-auth-pages")
    || Array.from(document.querySelectorAll(".page-signQR, [class*='pageSignQR'], .input-field-phone")).some(shown);
  const chats = !!document.querySelector("#column-left .chatlist-chat");
  if (chats && !auth) { return "connected"; }
  if (auth) { return "login"; }
  const text = body.innerText.toLowerCase();
  if (text.includes("browser is not supported") || text.includes("update your browser")) { return "unsupported"; }
  return "loading";
  """#

  static let openChat = lookups + #"""
  const header = activeChat() && activeChat().querySelector(".chat-info .peer-title, .chat-info .user-title");
  if (header && nameMatches(readText(header))) { return "open"; }
  const row = pickByName(chatRows());
  if (!row) { return ""; }
  fire(row);
  return "clicked";
  """#

  static let search = #"""
  const box = document.querySelector("#column-left .input-search input, #column-left input.input-search-input");
  if (!box || nameList.length === 0) { return ""; }
  return (await typeInto(box, nameList[0])) ? "typed" : "";
  """#

  static let activeChat = lookups + #"""
  const scope = activeChat();
  const header = scope && scope.querySelector(".chat-info .peer-title, .chat-info .user-title");
  return !!header && nameMatches(readText(header));
  """#

  static let compose = lookups + #"""
  const box = composer();
  if (!box) { return "nocomposer"; }
  return (await typeInto(box, String(text))) ? "ok" : "empty";
  """#

  static let send = lookups + #"""
  const before = outgoing().length;
  const scope = activeChat();
  const button = scope && scope.querySelector(".btn-send.send, .btn-send");
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
  if (last && sample !== "" && bare(readText(last.querySelector(".message") || last)).includes(sample)) { return "sent"; }
  return list.length === 0 ? "sent" : "pending";
  """#
}
