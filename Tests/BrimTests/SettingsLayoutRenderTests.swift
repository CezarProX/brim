import AppKit
import SwiftUI
import Testing

@testable import Brim

/// Renders the Settings window (860×640) on its first pane and on each grouped feature pane, so the
/// sidebar and pane layouts can be checked by eye. PNGs land in `.renders/settings-*.png`.
@MainActor
@Suite(.serialized)
struct SettingsLayoutRenderTests {
  private let size = SettingsWindowLayout.defaultSize

  @Test func settingsRoot() async throws {
    try await render(SettingsRootView(), name: "settings-root.png")
  }

  @Test(arguments: SettingsPane.allCases.map { ($0, $0.renderName) })
  func pane(_ pane: SettingsPane, file: String) async throws {
    try await render(SettingsRootView(initialPane: pane), name: "settings-\(file).png")
  }

  /// The whole Droplets pane unscrolled, to check the sections below the fold.
  @Test func dropletsPaneFullLength() async throws {
    let tall = CGSize(width: 596, height: 900)
    let view = Form {
      TermiNotchSettingsSection(); TeleprompterSettingsSection(); TextCaptureSettingsSection(); DropClipSettingsSection()
    }
    .formStyle(.grouped).toggleStyle(.switch).frame(width: tall.width, alignment: .topLeading)
    try await render(view.frame(height: tall.height, alignment: .top), name: "settings-droplets-lower.png", size: tall)
  }

  @Test func everyPaneSitsInAGroupAndGroupsKeepSidebarOrder() {
    let order = SettingsPane.allCases.map(\.group)
    let firstIndex = SettingsPaneGroup.allCases.map { group in order.firstIndex(of: group) ?? -1 }
    #expect(!firstIndex.contains(-1), "every group has at least one pane")
    #expect(firstIndex == firstIndex.sorted(), "groups appear in sidebar order")
    let lastIndex = SettingsPaneGroup.allCases.map { group in order.lastIndex(of: group) ?? -1 }
    for (index, group) in SettingsPaneGroup.allCases.enumerated().dropLast() {
      #expect(lastIndex[index] < firstIndex[index + 1], "\(group) panes are contiguous")
    }
  }

  // MARK: Helpers

  private func render<V: View>(_ view: V, name: String, size: CGSize? = nil) async throws {
    let size = size ?? self.size
    let root = view.background(Color(nsColor: .windowBackgroundColor))
    let host = NSHostingView(rootView: root)
    host.frame = CGRect(origin: .zero, size: size)
    // A real (never shown) window, so onAppear work such as scrolling the sidebar to the pane runs.
    let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    defer { window.close() }
    host.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(300))
    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    let png = try #require(bitmap.representation(using: .png, properties: [:]))
    try png.write(to: rendersDirectory().appendingPathComponent(name))
  }

  private func rendersDirectory() throws -> URL {
    let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().appendingPathComponent(".renders")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }
}

extension SettingsPane {
  /// File-name stem for this page's renders.
  var renderName: String {
    rawValue.lowercased().replacingOccurrences(of: " & ", with: "-").replacingOccurrences(of: " ", with: "-")
  }
}
