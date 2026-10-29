// NotificationAppResolver.swift
// Brim
//
// Maps the app name read from a banner to a bundle id and icon, using running apps first
// and then a cached index of the standard application folders.

import AppKit

@MainActor
final class NotificationAppResolver {
  static let shared = NotificationAppResolver()

  private var index: [String: URL]?
  private var iconCache: [String: NSImage] = [:]

  func isAppName(_ name: String) -> Bool { appURL(named: name) != nil || runningApp(named: name) != nil }

  func bundleID(forName name: String) -> String? {
    if let running = runningApp(named: name)?.bundleIdentifier { return running }
    return appURL(named: name).flatMap { Bundle(url: $0)?.bundleIdentifier }
  }

  func displayName(forBundleID id: String) -> String {
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return id }
    return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
  }

  func icon(forBundleID id: String?) -> NSImage? {
    guard let id else { return nil }
    if let cached = iconCache[id] { return cached }
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
    let icon = NSWorkspace.shared.icon(forFile: url.path)
    iconCache[id] = icon
    return icon
  }

  private func runningApp(named name: String) -> NSRunningApplication? {
    NSWorkspace.shared.runningApplications.first { $0.localizedName == name && $0.activationPolicy != .prohibited }
  }

  private func appURL(named name: String) -> URL? {
    if index == nil { index = Self.buildIndex() }
    return index?[name.lowercased()]
  }

  private static func buildIndex() -> [String: URL] {
    let roots = ["/Applications", "/System/Applications", "/System/Applications/Utilities",
                 "/Applications/Utilities", NSHomeDirectory() + "/Applications"]
    var result: [String: URL] = [:]
    for root in roots {
      let urls = (try? FileManager.default.contentsOfDirectory(
        at: URL(fileURLWithPath: root), includingPropertiesForKeys: nil)) ?? []
      for url in urls where url.pathExtension == "app" {
        result[url.deletingPathExtension().lastPathComponent.lowercased()] = url
      }
    }
    return result
  }
}
