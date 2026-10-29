import Foundation
import Testing

@testable import Brim

struct CodingAgentParserTests {
  private func line(_ object: [String: Any]) -> Data {
    try! JSONSerialization.data(withJSONObject: object)
  }

  @Test func claudeRunningToolWithTokensAndTurns() throws {
    let lines = [
      line(["type": "user", "timestamp": "2026-09-24T15:00:00.000Z", "message": ["role": "user", "content": "port the island"]]),
      line(["type": "assistant", "timestamp": "2026-09-24T15:00:05.000Z", "message": [
        "role": "assistant", "model": "claude-opus-5-5", "stop_reason": "tool_use",
        "usage": ["input_tokens": 10, "cache_read_input_tokens": 80_000, "cache_creation_input_tokens": 2_000, "output_tokens": 500],
        "content": [["type": "tool_use", "name": "Read", "input": ["file_path": "/tmp/nz_2.png"]]],
      ]]),
      line(["type": "user", "message": ["role": "user", "content": [["type": "tool_result", "content": "ok"]]]]),
      line(["type": "assistant", "message": [
        "role": "assistant", "model": "claude-opus-5-5", "stop_reason": "tool_use",
        "usage": ["input_tokens": 12, "cache_read_input_tokens": 81_000, "output_tokens": 300],
        "content": [["type": "tool_use", "name": "Bash", "input": ["command": "grep -n x", "description": "grep -n"]]],
      ]]),
    ]
    let session = try #require(CodingAgentParser.claude(lines: lines, modified: .now))
    #expect(session.model == "Opus 5.5")
    #expect(session.state == .running("Running grep -n"))
    #expect(session.steps == ["Running grep -n", "Reading nz_2.png"])
    #expect(session.outputTokens == 800)
    #expect(session.contextTokens == 81_012)
    #expect(session.turns == 1)
  }

  @Test func claudeEndTurnWaitsForTheUser() throws {
    let lines = [
      line(["type": "user", "message": ["role": "user", "content": "hi"]]),
      line(["type": "assistant", "message": [
        "role": "assistant", "stop_reason": "end_turn",
        "content": [["type": "text", "text": "All set."]],
      ]]),
    ]
    let session = try #require(CodingAgentParser.claude(lines: lines, modified: .now))
    #expect(session.state == .waiting)
    #expect(session.lastMessage == "All set.")
  }

  @Test func codexTracksToolsTokensAndCompletion() throws {
    let lines = [
      line(["type": "event_msg", "timestamp": "2026-09-24T14:44:55.939Z", "payload": ["type": "user_message", "message": "go"]]),
      line(["type": "response_item", "payload": ["type": "function_call", "name": "shell"]]),
      line(["type": "event_msg", "payload": ["type": "token_count", "info": ["total_token_usage": ["total_tokens": 17_800]]]]),
    ]
    let running = try #require(CodingAgentParser.codex(lines: lines, modified: .now))
    #expect(running.state == .running("Running shell"))
    #expect(running.outputTokens == 17_800)
    let done = try #require(
      CodingAgentParser.codex(lines: lines + [line(["type": "event_msg", "payload": ["type": "task_complete"]])], modified: .now))
    #expect(done.state == .waiting)
  }

  @Test func ignoresGarbageAndOldSessions() {
    #expect(CodingAgentParser.claude(lines: [Data("not json".utf8)], modified: .now) == nil)
    let session = CodingAgentSession(
      tool: .claude, model: nil, state: .thinking, steps: [], lastMessage: nil, outputTokens: 0,
      contextTokens: 0, turns: 0, started: nil, updated: Date(timeIntervalSinceNow: -600))
    #expect(!session.isLive())
  }

  @Test func contextWindowGrowsToOneMillionOnceAStandardWindowIsExceeded() {
    #expect(CodingAgentParser.contextWindow(for: 84_000) == 200_000)
    #expect(CodingAgentParser.contextWindow(for: 200_000) == 200_000)
    #expect(CodingAgentParser.contextWindow(for: 420_000) == 1_000_000)
  }

  @Test func projectComesFromTheCwdTheSessionStartedIn() {
    let claude = [
      line(["type": "summary"]),
      line(["type": "user", "cwd": "/Users/me/Project Local/aitrader", "message": ["content": "hi"]]),
      line(["type": "assistant", "cwd": "/Users/me/Project Local/aitrader/src", "message": ["content": []]]),
    ]
    #expect(CodingAgentParser.project(lines: claude) == "aitrader")
    let codex = [line(["type": "session_meta", "payload": ["cwd": "/Users/me/screenshot app"]])]
    #expect(CodingAgentParser.project(lines: codex) == "screenshot app")
    #expect(CodingAgentParser.project(lines: [Data("garbage".utf8)]) == nil)
  }

  private func session(_ id: String, ago: TimeInterval, state: CodingAgentSession.State = .thinking) -> CodingAgentSession {
    CodingAgentSession(
      tool: .claude, model: nil, state: state, steps: [], lastMessage: nil, outputTokens: 0,
      contextTokens: 0, turns: 0, started: nil, updated: Date(timeIntervalSinceNow: -ago), id: id)
  }

  @Test func pinnedSessionStaysWhileOthersKeepWriting() {
    let sessions = [session("a", ago: 1), session("b", ago: 20), session("c", ago: 40)]
    #expect(CodingAgentModel.pick(sessions, pinned: "b")?.id == "b")
    #expect(CodingAgentModel.pick(sessions, pinned: nil)?.id == "a")
  }

  @Test func pinFallsBackWhenItsSessionEnds() {
    let sessions = [session("a", ago: 1), session("b", ago: 90, state: .waiting)]
    #expect(CodingAgentModel.pick(sessions, pinned: "b")?.id == "a")
    #expect(CodingAgentModel.pick(sessions, pinned: "gone")?.id == "a")
    #expect(CodingAgentModel.pick([], pinned: "a") == nil)
  }
}

struct BrowserSnapshotTests {
  @Test func parsesActiveTabCountAndOthers() throws {
    let text = "GitHub\thttps://github.com/\t12\nNew Tab\tchrome://newtab/\nDocs\thttps://www.apple.com/x"
    let snapshot = try #require(BrowserSnapshot.parse(text, browser: .chrome))
    #expect(snapshot.active.title == "GitHub")
    #expect(snapshot.active.host == "github.com")
    #expect(snapshot.tabCount == 12)
    #expect(snapshot.others.map(\.host) == ["newtab", "apple.com"])
    #expect(BrowserSnapshot.parse("", browser: .safari) == nil)
    #expect(BrowserSnapshot.parse("title only", browser: .safari) == nil)
  }
}
