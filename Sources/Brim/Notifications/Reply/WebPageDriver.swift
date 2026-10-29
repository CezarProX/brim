// WebPageDriver.swift
// Brim
//
// The seam between the reply logic and WebKit. `WebPageDriving` is what the session and the
// send flow talk to; tests substitute a fake page. Values cross as small Sendable enums.

import AppKit

/// A script argument. Passed to the page as a JavaScript value, never as source text.
enum WebArgument: Equatable, Sendable {
  case string(String)
  case strings([String])
  case number(Double)

  var javaScriptValue: Any {
    switch self {
    case .string(let value): return value
    case .strings(let values): return values
    case .number(let value): return value
    }
  }
}

/// What a page script returned.
enum WebValue: Equatable, Sendable {
  case string(String)
  case number(Double)
  case bool(Bool)
  case none

  init(_ raw: Any?) {
    switch raw {
    case let value as String: self = .string(value)
    case let value as NSNumber where CFGetTypeID(value) == CFBooleanGetTypeID(): self = .bool(value.boolValue)
    case let value as NSNumber: self = .number(value.doubleValue)
    case let value as Bool: self = .bool(value)
    default: self = .none
    }
  }

  var string: String {
    if case .string(let value) = self { return value }
    return ""
  }

  var bool: Bool {
    switch self {
    case .bool(let value): return value
    case .number(let value): return value != 0
    case .string(let value): return !value.isEmpty
    case .none: return false
    }
  }

  var number: Double? {
    if case .number(let value) = self { return value }
    return nil
  }
}

@MainActor
protocol WebPageDriving: AnyObject {
  func load(_ url: URL)
  func run(_ script: WebScript, arguments: [String: WebArgument]) async throws -> WebValue
  /// The live page view, shown in the connect window while the user scans the code.
  var pageView: NSView? { get }
  /// Puts the page back into its hidden window after the connect window closes.
  func returnToKeepAlive()
  /// Deletes cookies and storage: signs this Mac's linked session out locally.
  func eraseData() async
  func tearDown()
}

/// A borderless, click-through window that holds the hidden page. WebKit only renders and runs
/// animation frames for pages it considers visible, and a window entirely off screen counts as
/// occluded (Telegram Web then never draws). So the window is parked just outside a bottom
/// corner of the main screen with a single, near-transparent pixel still on screen (one corner per
/// messenger, so two windows never cover each other). It never
/// becomes key or main, ignores the mouse, follows every Space and is excluded from capture.
final class WebKeepAliveWindow: NSWindow {
  static let size = CGSize(width: 1100, height: 820)

  private let slot: Int

  init(slot: Int = 0) {
    self.slot = slot
    super.init(contentRect: CGRect(origin: .zero, size: Self.size), styleMask: [.borderless],
               backing: .buffered, defer: false)
    isReleasedWhenClosed = false
    ignoresMouseEvents = true
    hasShadow = false
    isOpaque = false
    alphaValue = 0.01
    level = .statusBar
    sharingType = .none
    animationBehavior = .none
    isExcludedFromWindowsMenu = true
    collectionBehavior = [.ignoresCycle, .stationary, .transient, .canJoinAllSpaces, .fullScreenAuxiliary]
    park()
  }

  /// Leaves exactly one pixel of the window on the main screen. Call again when displays change.
  func park() {
    let screen = NSScreen.screens.first?.frame ?? .zero
    setFrameOrigin(Self.parkedOrigin(screen: screen, size: frame.size, slot: slot))
  }

  /// Slot 0 shows its top-right pixel at the bottom-left corner; slot 1 its top-left pixel at the
  /// bottom-right corner.
  static func parkedOrigin(screen: CGRect, size: CGSize, slot: Int) -> CGPoint {
    let x = slot == 0 ? screen.minX - size.width + 1 : screen.maxX - 1
    return CGPoint(x: x, y: screen.minY - size.height + 1)
  }

  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
  override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}
