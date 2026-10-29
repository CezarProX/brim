import Testing

@testable import Brim

/// What the approval card shows must be what runs: no bidi tricks, no control characters.
struct AgentQuestionCleanTests {
  @Test func bidiControlsAreRemoved() {
    let tricked = "rm -rf ~/\u{202E}txt.exe\u{202C} \u{2066}x\u{2069}\u{200F}"
    #expect(AgentQuestionRequest.clean(tricked, limit: 600) == "rm -rf ~/txt.exe x")
  }

  @Test func newlinesStayOnlyWhenMultiline() {
    #expect(AgentQuestionRequest.clean("a\nb", limit: 10) == "a\nb")
    #expect(AgentQuestionRequest.clean("a\nb", limit: 10, multiline: false) == "ab")
  }
}
