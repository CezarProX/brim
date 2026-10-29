import AppKit
import ApplicationServices
import SwiftUI
import Testing

@testable import Brim

/// Renders the agent and meeting views to `.renders/` so the design can be inspected, and checks the obvious facts.
@MainActor
@Suite(.serialized)
struct AgentMeetingRenderTests {
  private func session(
    _ tool: CodingAgentSession.Tool, _ state: CodingAgentSession.State, project: String, steps: [String] = [],
    message: String? = nil, added: Int = 0, removed: Int = 0, file: String? = nil
  ) -> CodingAgentSession {
    var session = CodingAgentSession(
      tool: tool, model: tool == .claude ? "Opus 5.5" : nil, state: state, steps: steps, lastMessage: message,
      outputTokens: 18_400, contextTokens: tool == .claude ? 96_000 : 0, turns: 4,
      started: Date(timeIntervalSinceNow: -754), updated: .now, id: "/\(tool.rawValue)", project: project)
    session.linesAdded = added
    session.linesRemoved = removed
    session.currentFile = file
    if tool == .cursor { session.contextFraction = 0.42 }
    return session
  }

  @Test func expandedClaudeRunningAToolWithUsageRing() async throws {
    let claude = session(
      .claude, .running("Editing CodingAgentModel.swift"), project: "screenshot app",
      steps: ["Editing CodingAgentModel.swift", "Reading AppSkinViews.swift", "Running swift test"], added: 128, removed: 31,
      file: "CodingAgentModel.swift")
    let usage = UsageReading(fraction: 0.82, resetsAt: Date(timeIntervalSinceNow: 5400), used: 1_640_000, limit: 2_000_000)
    let bitmap = try await render(
      CodingAgentView(session: claude, sessions: [claude], usage: usage), name: "agent-claude-running-usage82",
      size: CGSize(width: 440, height: 170))
    #expect(bitmap.pixelsWide > 0)
    #expect(AgentUsageRing.color(fraction: usage.fraction, base: .blue) == .orange)
  }

  @Test func expandedCursorWaitingForYou() async throws {
    let cursor = session(
      .cursor, .needsInput("Approve: Running a command"), project: "web-app", added: 42, removed: 7, file: "auth.ts")
    let other = session(.codex, .running("Running shell"), project: "api")
    _ = try await render(
      CodingAgentView(session: cursor, sessions: [cursor, other], usage: nil), name: "agent-cursor-waiting",
      size: CGSize(width: 440, height: 170))
  }

  @Test func expandedOpenCodeAndAntigravityDone() async throws {
    let open = session(.openCode, .waiting, project: "site", message: "Refactored the header into three components.", added: 12, removed: 3)
    _ = try await render(
      CodingAgentView(session: open, sessions: [open], usage: nil), name: "agent-opencode-done", size: CGSize(width: 440, height: 150))
    let anti = session(.antigravity, .running("Edit `src/Process.tsx`"), project: "Redesign Cards", steps: ["Edit `src/Process.tsx`"])
    _ = try await render(
      CodingAgentView(session: anti, sessions: [anti], usage: nil), name: "agent-antigravity-running", size: CGSize(width: 440, height: 150))
  }

  @Test func compactWingsForEveryAgent() async throws {
    func wing(_ tool: CodingAgentSession.Tool, usage: Double?, attention: Bool, state: CodingAgentSession.State) -> some View {
      HStack(spacing: 10) {
        AgentGlyph(tool: tool, size: 22, usageFraction: usage, attention: attention, vectorOnly: true)
        AgentStateIndicator(session: session(tool, state, project: "p"))
      }
      .padding(.horizontal, 12).frame(height: 34).background(.black, in: Capsule())
      .overlay(Capsule().stroke(.white.opacity(0.12)))
    }
    let sheet = VStack(alignment: .leading, spacing: 10) {
      wing(.claude, usage: 0.40, attention: false, state: .running("x"))
      wing(.claude, usage: 0.82, attention: false, state: .running("x"))
      wing(.codex, usage: 0.96, attention: false, state: .waiting)
      wing(.cursor, usage: nil, attention: true, state: .needsInput("Approve"))
      wing(.openCode, usage: nil, attention: false, state: .thinking)
      wing(.antigravity, usage: nil, attention: false, state: .running("x"))
    }
    .padding(16)
    _ = try await render(sheet, name: "agent-compact-wings", size: CGSize(width: 150, height: 330))
    let mascots = HStack(spacing: 18) {
      ForEach(CodingAgentSession.Tool.allCases, id: \.rawValue) { AgentMascot(tool: $0, size: 56) }
    }.padding(20)
    _ = try await render(mascots, name: "agent-mascots", size: CGSize(width: 420, height: 100))
  }

  @Test func meetingControlsShowMutedState() async throws {
    let settings = AppSettings(defaults: UserDefaults(suiteName: "render-\(UUID().uuidString)")!)
    let snapshot = CallSnapshot(
      process: CallProcess(pid: ProcessInfo.processInfo.processIdentifier, app: .zoom, isBrowser: false),
      window: AXUIElementCreateSystemWide(), scope: AXUIElementCreateSystemWide(), title: "Design review", controls: [],
      evidence: CallEvidence(
        endLabel: "leave", muteLabel: "unmute", cameraLabel: "start video", screenShareLabel: "share screen",
        isMuted: true, isCameraOn: false, isScreenSharing: false))
    let model = CallActivityModel(
      settings: settings, accessibilityTrusted: { true }, requestPermission: {}, microphoneInUse: { true },
      scan: { _ in snapshot })
    model.refresh()
    try await Task.sleep(for: .milliseconds(300))
    #expect(model.activeCall?.isMuted == true)
    #expect(model.canToggleCamera && model.canToggleScreenShare)
    _ = try await render(
      CallActivityView(model: model, embedded: true).padding(16), name: "meeting-controls-muted",
      size: CGSize(width: 440, height: 200))
    let compact = HStack(spacing: 16) {
      CallCompactGlyph(mutedOverride: false)
      CallCompactGlyph(mutedOverride: true)
      MutedBadge()
    }.padding(14)
    _ = try await render(compact, name: "meeting-compact-glyphs", size: CGSize(width: 200, height: 56))
  }

  private func render<V: View>(_ view: V, name: String, size: CGSize) async throws -> NSBitmapImageRep {
    let host = NSHostingView(
      rootView: view.frame(width: size.width, height: size.height, alignment: .topLeading)
        .foregroundStyle(.white).background(.black).preferredColorScheme(.dark))
    let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    defer { window.close() }
    host.frame = CGRect(origin: .zero, size: size)
    host.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(150))
    host.layoutSubtreeIfNeeded()
    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().appendingPathComponent(".renders", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try #require(bitmap.representation(using: .png, properties: [:])).write(to: directory.appendingPathComponent(name + ".png"))
    return bitmap
  }
}
