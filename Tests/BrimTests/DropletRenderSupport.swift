import AppKit
import SwiftUI
import Testing

@testable import Brim

/// Renders a SwiftUI view to `.renders/<name>` in the worktree so the design can be looked at.
@MainActor
enum DropletRender {
  static func isolatedSettings() -> AppSettings {
    AppSettings(defaults: UserDefaults(suiteName: "QS-Droplet-\(UUID().uuidString)")!)
  }

  static func url(_ name: String) throws -> URL {
    var root = URL(fileURLWithPath: #filePath)
    while root.pathComponents.count > 1,
      !FileManager.default.fileExists(atPath: root.appendingPathComponent("Package.swift").path)
    {
      root.deleteLastPathComponent()
    }
    let folder = root.appendingPathComponent(".renders", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder.appendingPathComponent(name)
  }

  @discardableResult
  static func png<V: View>(_ view: V, size: CGSize, name: String, background: Color = Color(white: 0.16)) async throws -> NSBitmapImageRep {
    let host = NSHostingView(
      rootView: view.frame(width: size.width, height: size.height).background(background).preferredColorScheme(.dark))
    let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    defer { window.close() }
    host.frame = CGRect(origin: .zero, size: size)
    host.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(900))
    host.layoutSubtreeIfNeeded()
    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    if let data = bitmap.representation(using: .png, properties: [:]) { try data.write(to: url(name)) }
    return bitmap
  }
}
