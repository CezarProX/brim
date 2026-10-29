// SelectionReader.swift
// Brim
//
// Reads the text selected in the frontmost app: first the Accessibility API (no side effects),
// then, if allowed, a synthetic ⌘C with the pasteboard saved and restored around it.

import AppKit
import ApplicationServices
import Carbon.HIToolbox

struct SelectionSnapshot: Equatable {
  var text: String
  /// Selection bounds in Cocoa screen coordinates, when the app reports them.
  var bounds: CGRect?
  var bundleID: String?
  var appName: String?
}

@MainActor
enum SelectionReader {
  static var isTrusted: Bool { AXIsProcessTrusted() }

  static func requestTrust() {
    _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
  }

  static func read(allowCopyFallback: Bool) async -> SelectionSnapshot? {
    let app = NSWorkspace.shared.frontmostApplication
    let bundle = app?.bundleIdentifier
    guard bundle != Bundle.main.bundleIdentifier else { return nil }
    if let viaAX = accessibilitySelection(), !viaAX.text.isEmpty {
      return SelectionSnapshot(text: viaAX.text, bounds: viaAX.bounds, bundleID: bundle, appName: app?.localizedName)
    }
    guard allowCopyFallback, isTrusted, let copied = await copySelection(), !copied.isEmpty else { return nil }
    return SelectionSnapshot(text: copied, bounds: nil, bundleID: bundle, appName: app?.localizedName)
  }

  // MARK: Accessibility

  private static func accessibilitySelection() -> (text: String, bounds: CGRect?)? {
    guard isTrusted else { return nil }
    let system = AXUIElementCreateSystemWide()
    var focused: CFTypeRef?
    guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
      let element = focused, CFGetTypeID(element) == AXUIElementGetTypeID()
    else { return nil }
    let ax = element as! AXUIElement  // type checked above
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(ax, kAXSelectedTextAttribute as CFString, &value) == .success,
      let text = value as? String
    else { return nil }
    return (text, selectionBounds(of: ax))
  }

  private static func selectionBounds(of element: AXUIElement) -> CGRect? {
    var rangeValue: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeValue) == .success,
      let range = rangeValue
    else { return nil }
    var boundsValue: CFTypeRef?
    guard AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString, range, &boundsValue) == .success,
      let bounds = boundsValue, CFGetTypeID(bounds) == AXValueGetTypeID()
    else { return nil }
    var rect = CGRect.zero
    guard AXValueGetValue(bounds as! AXValue, .cgRect, &rect), rect.width > 0 || rect.height > 0 else { return nil }
    return cocoaRect(fromAX: rect)
  }

  /// Accessibility uses a top-left origin on the primary screen; Cocoa uses bottom-left.
  static func cocoaRect(fromAX rect: CGRect, primaryHeight: CGFloat? = nil) -> CGRect {
    let height = primaryHeight ?? NSScreen.screens.first?.frame.height ?? 0
    return CGRect(x: rect.minX, y: height - rect.maxY, width: rect.width, height: rect.height)
  }

  // MARK: Copy fallback

  private static func copySelection() async -> String? {
    let board = NSPasteboard.general
    let saved = snapshot(board)
    let before = board.changeCount
    postCommandC()
    var copied: String?
    for _ in 0..<14 {
      try? await Task.sleep(for: .milliseconds(30))
      if board.changeCount != before {
        copied = board.string(forType: .string)
        break
      }
    }
    if board.changeCount != before { restore(saved, to: board) }
    return copied
  }

  private static func snapshot(_ board: NSPasteboard) -> [[(NSPasteboard.PasteboardType, Data)]] {
    (board.pasteboardItems ?? []).map { item in item.types.compactMap { type in item.data(forType: type).map { (type, $0) } } }
  }

  private static func restore(_ saved: [[(NSPasteboard.PasteboardType, Data)]], to board: NSPasteboard) {
    board.clearContents()
    let items = saved.map { entries -> NSPasteboardItem in
      let item = NSPasteboardItem()
      for (type, data) in entries { item.setData(data, forType: type) }
      return item
    }
    if !items.isEmpty { board.writeObjects(items) }
  }

  private static func postCommandC() {
    let source = CGEventSource(stateID: .combinedSessionState)
    for down in [true, false] {
      let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: down)
      event?.flags = .maskCommand  // explicit, so a still-held shortcut modifier can't change the chord
      event?.post(tap: .cghidEventTap)
    }
  }
}
