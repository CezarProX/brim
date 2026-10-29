import AppKit
import ApplicationServices
import Foundation

/// Lists a browser's windows and which are private. Best effort, never prompts:
/// Chrome-family browsers answer through Apple Events (`mode of window` is "incognito"),
/// everything else through Accessibility window titles when Accessibility is already granted.
enum BrowserWindowProbe {
  static let chromeFamily: Set<String> = [
    "com.google.Chrome", "com.google.Chrome.beta", "com.brave.Browser", "com.microsoft.edgemac", "com.vivaldi.Vivaldi",
    "company.thebrowser.Browser",
  ]

  static func windows(bundleID: String) -> [BrowserWindowInfo] {
    guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { return [] }
    if chromeFamily.contains(bundleID), let viaScript = chromeWindows(bundleID: bundleID) { return viaScript }
    return accessibilityWindows(pid: app.processIdentifier)
  }

  private static func accessibilityWindows(pid: pid_t) -> [BrowserWindowInfo] {
    guard AXIsProcessTrusted() else { return [] }
    let app = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(app, 0.5)
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
          let windows = value as? [AXUIElement] else { return [] }
    return windows.compactMap { window in
      var title: CFTypeRef?
      guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &title) == .success,
            let text = title as? String else { return nil }
      return BrowserWindowInfo(title: text, isPrivate: MediaVisibilityRules.titleLooksPrivate(text))
    }
  }

  /// Only when the browser is running (the guard avoids launching it) and Automation consent exists.
  private static func chromeWindows(bundleID: String) -> [BrowserWindowInfo]? {
    let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
    guard AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, false) == noErr else { return nil }
    let source = """
      tell application id "\(bundleID)"
        set out to ""
        repeat with w in windows
          set out to out & (mode of w) & (ASCII character 31) & (title of active tab of w) & (ASCII character 30)
        end repeat
        return out
      end tell
      """
    var error: NSDictionary?
    guard let result = NSAppleScript(source: source)?.executeAndReturnError(&error).stringValue else { return nil }
    return parseChromeWindows(result)
  }

  static func parseChromeWindows(_ text: String) -> [BrowserWindowInfo] {
    text.split(separator: "\u{1E}").compactMap { record in
      let parts = record.split(separator: "\u{1F}", maxSplits: 1, omittingEmptySubsequences: false)
      guard parts.count == 2 else { return nil }
      return BrowserWindowInfo(title: String(parts[1]), isPrivate: parts[0] == "incognito")
    }
  }
}
