import ApplicationServices
import AppKit

/// A session event tap that sees media keys and ⌘Q. The handler runs on the main thread and
/// returns true to swallow the event.
@MainActor
final class MediaKeyTap {
  typealias Handler = @MainActor (CGEventType, CGEvent) -> Bool
  private var tap: CFMachPort?
  private var source: CFRunLoopSource?
  private let handler: Handler

  init(handler: @escaping Handler) { self.handler = handler }

  var isRunning: Bool { tap != nil }

  static var isTrusted: Bool { AXIsProcessTrusted() }

  /// Shows the system Accessibility prompt (once per launch) and returns the current trust.
  @discardableResult
  static func requestTrust() -> Bool {
    let key = "AXTrustedCheckOptionPrompt" as CFString
    return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
  }

  /// Installs the tap. Returns false without Accessibility trust or if the system refuses.
  @discardableResult
  func start(includingKeyDown: Bool = false) -> Bool {
    if tap != nil, includingKeyDown == watchesKeyDown { return true }
    stop()
    guard Self.isTrusted else { return false }
    // Ordinary key presses only pass through this tap when the ⌘Q guard needs them: an active tap
    // on every keystroke makes the whole system's typing wait on this app's main thread.
    var mask = CGEventMask(1 << MediaKeyEvent.systemDefinedType)
    if includingKeyDown { mask |= CGEventMask(1 << CGEventType.keyDown.rawValue) }
    watchesKeyDown = includingKeyDown
    let callback: CGEventTapCallBack = { _, type, event, refcon in
      guard let refcon else { return Unmanaged.passUnretained(event) }
      let tap = Unmanaged<MediaKeyTap>.fromOpaque(refcon).takeUnretainedValue()
      let consumed = MainActor.assumeIsolated { tap.dispatch(type, event) }
      return consumed ? nil : Unmanaged.passUnretained(event)
    }
    guard
      let port = CGEvent.tapCreate(
        tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask,
        callback: callback, userInfo: Unmanaged.passUnretained(self).toOpaque())
    else { return false }
    let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
    CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
    CGEvent.tapEnable(tap: port, enable: true)
    tap = port
    source = runLoopSource
    return true
  }

  private var watchesKeyDown = false

  func stop() {
    if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
    if let tap {
      CGEvent.tapEnable(tap: tap, enable: false)
      CFMachPortInvalidate(tap)
    }
    tap = nil
    source = nil
  }

  private func dispatch(_ type: CGEventType, _ event: CGEvent) -> Bool {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
      return false
    }
    return handler(type, event)
  }
}
