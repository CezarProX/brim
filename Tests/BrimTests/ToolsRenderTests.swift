import AppKit
import SwiftUI
import Testing

@testable import Brim

@MainActor
@Suite(.serialized)
struct ToolsRenderTests {
  private func launcherModel(_ query: String) -> ThunderstormModel {
    let settings = DropletRender.isolatedSettings()
    settings.thunderstormSnippets = [ThunderSnippet(keyword: ";sig", title: "Email signature", text: "Best regards, Alex")]
    let apps = ["Safari", "Slack", "Spotify", "Sketch", "System Settings"].map {
      InstalledApp(name: $0, url: URL(fileURLWithPath: "/Applications/\($0).app"), bundleID: "com.example.\($0)")
    }
    let model = ThunderstormModel(settings: settings, apps: apps)
    model.query = query
    return model
  }

  @Test func rendersTheLauncher() async throws {
    for (name, query) in [("launcher-apps.png", "s"), ("launcher-calc.png", "12 * (3 + 4) + 20% of 50"), ("launcher-empty.png", "")] {
      let model = launcherModel(query)
      let view = ThunderstormView(model: model).frame(width: 700, height: 560, alignment: .top)
      let bitmap = try await DropletRender.png(view, size: CGSize(width: 700, height: 560), name: name, background: Color(white: 0.35))
      #expect(bitmap.pixelsWide > 0)
    }
    let model = launcherModel("trash")
    model.activate(index: 0)  // first Return on a destructive command only asks
    #expect(model.confirming != nil)
    try await DropletRender.png(ThunderstormView(model: model).frame(width: 700, height: 560, alignment: .top), size: CGSize(width: 700, height: 560), name: "launcher-confirm.png", background: Color(white: 0.35))
  }
}
