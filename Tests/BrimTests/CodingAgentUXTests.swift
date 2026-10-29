import Foundation
import Testing

@testable import Brim

struct CodingAgentUXTests {
  private func session(_ id: String, _ state: CodingAgentSession.State, ago: TimeInterval = 1) -> CodingAgentSession {
    CodingAgentSession(
      tool: .claude, model: nil, state: state, steps: [], lastMessage: nil, outputTokens: 0,
      contextTokens: 0, turns: 0, started: nil, updated: Date(timeIntervalSinceNow: -ago), id: id)
  }

  @Test func eachStepGetsTheGlyphOfWhatItDoes() {
    let cases = [
      ("Reading shot.png", "doc.text"), ("Editing Model.swift", "pencil"), ("Writing notes.md", "square.and.pencil"),
      ("Running swift test", "terminal"), ("Running shell", "terminal"), ("Searching pattern", "magnifyingglass"),
      ("Finding files", "folder"), ("Browsing the web", "globe"), ("Delegating to an agent", "person.2"),
      ("Using apply_patch", "wrench.and.screwdriver"), ("TodoWrite", "sparkle"),
    ]
    for (step, glyph) in cases { #expect(CodingAgentParser.symbol(for: step) == glyph, "\(step)") }
  }

  @Test func finishingATurnIsDetectedOncePerTransition() {
    let before = [session("a", .running("Running tests")), session("b", .thinking), session("c", .waiting)]
    let after = [session("a", .waiting), session("b", .thinking), session("c", .waiting), session("d", .waiting)]
    #expect(CodingAgentModel.finished(previous: before, next: after).map(\.id) == ["a"])
    #expect(CodingAgentModel.finished(previous: after, next: after).isEmpty)
  }

  @Test func stateReadsLikeAStatusNotATokenCount() {
    #expect(session("a", .running("x")).isWorking)
    #expect(session("a", .thinking).isWorking)
    #expect(!session("a", .waiting).isWorking)
    #expect(session("a", .waiting).statusText == "Your turn")
    #expect(session("a", .thinking).statusText == "Thinking")
    #expect(session("a", .running("x")).statusText == "Working")
  }

  @Test func sessionFileNamesTheProcessAndItsParentAppOwnsIt() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sessions-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try Data(#"{"pid":4242,"sessionId":"8df4aa24-abcd","cwd":"/x"}"#.utf8).write(to: dir.appendingPathComponent("4242.json"))
    try Data(#"{"pid":7,"sessionId":"other"}"#.utf8).write(to: dir.appendingPathComponent("7.json"))
    #expect(CodingAgentLocator.processID(forSession: "8df4aa24-abcd", in: dir) == 4242)
    #expect(CodingAgentLocator.processID(forSession: "missing", in: dir) == nil)
    // claude (4242) → node (300) → Antigravity Helper (200) → Antigravity.app (100)
    let parents: [Int32: Int32] = [4242: 300, 300: 200, 200: 100, 100: 1]
    let apps: Set<Int32> = [100]
    #expect(CodingAgentLocator.owningApp(of: 4242, parent: { parents[$0] }, isApp: { apps.contains($0) }) == 100)
    #expect(CodingAgentLocator.owningApp(of: 9, parent: { _ in 1 }, isApp: { _ in false }) == nil)
  }
}
