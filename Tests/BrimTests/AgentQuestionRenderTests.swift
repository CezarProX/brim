import AppKit
import SwiftUI
import Testing

@testable import Brim

@MainActor
@Suite("AgentQuestionRender", .serialized)
struct AgentQuestionRenderTests {
  private func make(_ object: [String: Any]) -> AgentQuestionRequest {
    var base: [String: Any] = ["agent": "claude", "cwd": "/Users/me/screenshot app", "sessionId": "s"]
    base.merge(object) { $1 }
    return try! AgentQuestionRequest.parse(try! JSONSerialization.data(withJSONObject: base))
  }

  @Test func rendersQuestionAndApprovalCards() async throws {
    let question = make([
      "question": "The release build is green. How do you want to ship the screenshot editor changes?",
      "options": [
        ["label": "Ship it now (Recommended)", "description": "Tag 1.4 and publish the update"],
        ["label": "Wait until Monday"], ["label": "Show me the changes first"],
      ],
    ])
    let multi = make(["agent": "codex", "question": "Which platforms should the build cover?", "multiSelect": true,
                      "options": ["macOS", "iOS", "Linux"]])
    let approval = make(["kind": "approval", "question": "Allow Bash? rm -rf node_modules && npm install", "options": [] as [Any]])
    let view = VStack(spacing: 16) {
      AgentQuestionCardView(request: question, waiting: 2)
      AgentQuestionCardView(request: multi)
      AgentQuestionCardView(request: approval)
    }
    .padding(24).background(Color(white: 0.2))
    let size = CGSize(width: 420, height: 880)
    let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height).preferredColorScheme(.dark))
    let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    defer { window.close() }
    host.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(600))
    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent(".renders")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try #require(bitmap.representation(using: .png, properties: [:])).write(to: dir.appendingPathComponent("agent-question-cards.png"))
  }

  @Test func hookConfirmationReadsPlainlyAndKeepsTheJSONInDetails() throws {
    let details = try #require(ClaudeHookInstallFlow.preview(existing: nil, command: "'/Applications/Brim.app/Contents/MacOS/Brim' --agent-hook"))
    let install = ClaudeHookInstallFlow.confirmation(details: details, repointing: false)
    #expect(install.title == "Let Brim answer Claude Code?" && install.confirmTitle == "Install" && install.cancelTitle == "Cancel")
    #expect(install.details?.contains("--agent-hook") == true)
    let visible = ([install.title, install.message ?? ""] + install.points.map(\.text)).joined(separator: " ")
    #expect(!visible.contains("{") && !visible.contains("agent-hook") && !visible.contains("PreToolUse"))
    let update = ClaudeHookInstallFlow.confirmation(details: details, repointing: true)
    #expect(update.confirmTitle == "Update" && update.title.contains("Brim"))
  }

  @Test func rendersHookConfirmation() async throws {
    let details = try #require(ClaudeHookInstallFlow.preview(existing: nil, command: "'/Applications/Brim.app/Contents/MacOS/Brim' --agent-hook"))
    let content = ClaudeHookInstallFlow.confirmation(details: details, repointing: false)
    let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent(".renders")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    for (name, scheme, expanded) in [("light", ColorScheme.light, false), ("dark", .dark, false), ("details", .dark, true)] {
      let view = BrimDialogView(content: content, icon: AppIconRenderer.image(for: .standard, size: 64),
                                detailsInitiallyShown: expanded) { _ in }
        .background(scheme == .dark ? Color(white: 0.17) : Color(white: 0.96))
        .environment(\.colorScheme, scheme)
      let host = NSHostingView(rootView: view)
      let size = host.fittingSize
      let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
      window.contentView = host
      defer { window.close() }
      host.layoutSubtreeIfNeeded()
      try await Task.sleep(for: .milliseconds(400))
      host.setFrameSize(host.fittingSize)
      let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
      host.cacheDisplay(in: host.bounds, to: bitmap)
      #expect(host.bounds.width == BrimDialogView.width)
      try #require(bitmap.representation(using: .png, properties: [:]))
        .write(to: dir.appendingPathComponent("agents-hook-confirm-\(name).png"))
    }
  }
}
