import Foundation
import Testing

@testable import Brim

struct AgentStateTests {
  private func line(_ object: [String: Any]) -> Data { try! JSONSerialization.data(withJSONObject: object) }

  private func claudeEdit(_ name: String, input: [String: Any]) -> [Data] {
    [
      line(["type": "user", "message": ["role": "user", "content": "go"]]),
      line(["type": "assistant", "message": [
        "role": "assistant", "stop_reason": "tool_use",
        "content": [["type": "tool_use", "name": name, "input": input]],
      ]]),
    ]
  }

  @Test func stalledEditWaitsForPermissionButAFreshOneIsRunning() throws {
    let lines = claudeEdit("Edit", input: ["file_path": "/p/Model.swift", "old_string": "a\nb", "new_string": "a\nb\nc\nd"])
    let modified = Date(timeIntervalSince1970: 1_000)
    let fresh = try #require(CodingAgentParser.claude(lines: lines, modified: modified, now: modified.addingTimeInterval(2)))
    #expect(fresh.state == .running("Editing Model.swift"))
    let stalled = try #require(CodingAgentParser.claude(lines: lines, modified: modified, now: modified.addingTimeInterval(12)))
    #expect(stalled.state == .needsInput("Approve: Editing Model.swift"))
    #expect(stalled.needsAttention && !stalled.isWorking)
    #expect(stalled.statusText == "Needs you")
    #expect(stalled.currentFile == "Model.swift")
    #expect(stalled.linesAdded == 4 && stalled.linesRemoved == 2)
  }

  @Test func aLongBashCommandIsNotMistakenForAPermissionPrompt() throws {
    let lines = claudeEdit("Bash", input: ["command": "swift test"])
    let modified = Date(timeIntervalSince1970: 1_000)
    let session = try #require(CodingAgentParser.claude(lines: lines, modified: modified, now: modified.addingTimeInterval(120)))
    #expect(session.state == .running("Running swift test"))
  }

  @Test func promotionAppliesToCachedSessionsAsTimePasses() throws {
    let lines = claudeEdit("Write", input: ["file_path": "/p/new.swift", "content": "x\ny\nz"])
    let modified = Date(timeIntervalSince1970: 1_000)
    let cached = try #require(CodingAgentParser.claude(lines: lines, modified: modified, now: modified.addingTimeInterval(1)))
    #expect(cached.state == .running("Writing new.swift"))
    #expect(cached.promotingStalledApproval(now: modified.addingTimeInterval(30)).needsAttention)
    #expect(cached.promotingStalledApproval(now: modified.addingTimeInterval(30)).promotingStalledApproval(now: modified.addingTimeInterval(60)).needsAttention)
    #expect(cached.linesAdded == 3)
  }

  @Test func codexApprovalRequestNeedsYouUntilTheCommandRuns() throws {
    let base = [line(["type": "event_msg", "payload": ["type": "user_message", "message": "go"]])]
    let asking = base + [line(["type": "event_msg", "payload": ["type": "exec_approval_request", "command": ["rm", "x"]]])]
    #expect(try #require(CodingAgentParser.codex(lines: asking, modified: .now)).state == .needsInput("Approve a command"))
    let ran = asking + [line(["type": "event_msg", "payload": ["type": "exec_command_begin"]])]
    #expect(try #require(CodingAgentParser.codex(lines: ran, modified: .now)).needsAttention == false)
  }

  @Test func codexPatchApprovalCountsDiffLines() throws {
    let changes: [String: Any] = [
      "/p/a.swift": ["update": ["unified_diff": "--- a\n+++ b\n@@\n-old\n+new1\n+new2\n"]],
      "/p/b.swift": ["add": ["content": "l1\nl2"]],
    ]
    let lines = [line(["type": "event_msg", "payload": ["type": "apply_patch_approval_request", "changes": changes]])]
    let session = try #require(CodingAgentParser.codex(lines: lines, modified: .now))
    #expect(session.state == .needsInput("Approve file changes"))
    #expect(session.linesAdded == 4 && session.linesRemoved == 1)
    #expect(session.currentFile == "a.swift")
  }

  @Test func lineCounterHandlesMultiEditAndIgnoresReads() {
    let multi = AgentLineCounter.change(
      tool: "MultiEdit", input: ["edits": [["old_string": "a", "new_string": "a\nb"], ["old_string": "c\nd", "new_string": "e"]]])
    #expect(multi.added == 3 && multi.removed == 3)
    #expect(AgentLineCounter.change(tool: "Read", input: ["file_path": "/x"]) == AgentLineCounter.Change())
    #expect(AgentLineCounter.lineCount("") == 0)
  }

  @Test func attentionIsAnnouncedOncePerTransition() {
    func session(_ id: String, _ state: CodingAgentSession.State) -> CodingAgentSession {
      CodingAgentSession(
        tool: .cursor, model: nil, state: state, steps: [], lastMessage: nil, outputTokens: 0, contextTokens: 0, turns: 0,
        started: nil, updated: .now, id: id)
    }
    let before = [session("a", .running("x")), session("b", .needsInput("Approve"))]
    let after = [session("a", .needsInput("Approve")), session("b", .needsInput("Approve")), session("c", .waiting)]
    #expect(CodingAgentModel.newlyNeedingAttention(previous: before, next: after).map(\.id) == ["a"])
    #expect(CodingAgentModel.newlyNeedingAttention(previous: after, next: after).isEmpty)
  }

  @Test func everyAgentHasABrandAndAnAppToJumpTo() {
    for tool in CodingAgentSession.Tool.allCases {
      #expect(!AgentBrand.bundleIDs(tool).isEmpty, "\(tool)")
    }
    #expect(Set(CodingAgentSession.Tool.allCases.map(\.settingsID)).count == CodingAgentSession.Tool.allCases.count)
  }
}
