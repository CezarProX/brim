import AppKit
import SwiftUI
import Testing

@testable import Brim

@MainActor
@Suite(.serialized)
struct ShellSettingsRenderTests {
    @Test func rendersTheSettingsSectionToPNG() async throws {
        let suite = "shell-render-\(UUID().uuidString)"
        let settings = AppSettings(defaults: UserDefaults(suiteName: suite)!)
        settings.shellHiddenApps = ["com.apple.finder", "com.apple.Safari"]
        settings.shellAnimationSpeed = .cheetah
        settings.shellExternalStyle = .island
        settings.shellIslandWidthOffset = 24
        let size = CGSize(width: 560, height: 1240)
        let view = Form { ShellSettingsSection(settings: settings, notifies: false) }.formStyle(.grouped).frame(width: size.width, height: size.height, alignment: .topLeading)
            .background(Color(nsColor: .windowBackgroundColor))
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        host.frame = CGRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(600))
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent(".renders")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("shell-settings.png")
        try png.write(to: file)
        #expect(bitmap.pixelsWide > 0)
    }
}
