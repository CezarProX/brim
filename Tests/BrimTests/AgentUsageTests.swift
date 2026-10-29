import Foundation
import Testing

@testable import Brim

struct AgentUsageTests {
  private let now = Date(timeIntervalSince1970: 1_800_000_000)
  private func sample(_ ago: TimeInterval, _ tokens: Int, key: String? = nil) -> UsageSample {
    UsageSample(date: now.addingTimeInterval(-ago), tokens: tokens, key: key ?? "k\(ago)-\(tokens)")
  }

  @Test func windowCountsOnlyTheLastFiveHours() {
    let samples = [sample(60, 1000), sample(4 * 3600, 2000), sample(5 * 3600 + 1, 9000), sample(10 * 3600, 5000)]
    #expect(AgentUsageMath.windowTokens(samples, now: now) == 3000)
  }

  @Test func boundaryAtExactlyFiveHoursIsInside() {
    #expect(AgentUsageMath.windowTokens([sample(5 * 3600, 700)], now: now) == 700)
  }

  @Test func duplicateMessagesAreCountedOnce() {
    let samples = [sample(10, 500, key: "m1:r1"), sample(9, 500, key: "m1:r1"), sample(8, 100, key: "m2:r2")]
    #expect(AgentUsageMath.windowTokens(samples, now: now) == 600)
  }

  @Test func futureSamplesAreIgnored() {
    #expect(AgentUsageMath.windowTokens([sample(-3600, 1000)], now: now) == 0)
  }

  @Test func readingIsAFractionOfTheLimitAndResetsWhenTheOldestAgesOut() throws {
    let samples = [sample(3 * 3600, 400_000), sample(60, 1_240_000)]
    let reading = try #require(AgentUsageMath.reading(samples, limit: 2_000_000, now: now))
    #expect(reading.percent == 82)
    #expect(reading.used == 1_640_000)
    #expect(reading.resetsAt == now.addingTimeInterval(-3 * 3600 + 5 * 3600))
    #expect(AgentUsageMath.reading([], limit: 2_000_000, now: now) == nil)
    let over = try #require(AgentUsageMath.reading([sample(1, 3_000_000)], limit: 2_000_000, now: now))
    #expect(over.fraction == 1)
  }

  @Test func transcriptLineSumsBilledTokensWithoutCacheReads() throws {
    let line = try JSONSerialization.data(withJSONObject: [
      "type": "assistant", "timestamp": "2026-10-22T10:00:00.000Z", "requestId": "req_1",
      "message": ["id": "msg_1", "usage": [
        "input_tokens": 10, "output_tokens": 200, "cache_creation_input_tokens": 300, "cache_read_input_tokens": 90_000,
      ]],
    ])
    let sample = try #require(AgentUsageMath.sample(line: line))
    #expect(sample.tokens == 510)
    #expect(sample.key == "msg_1:req_1")
    #expect(AgentUsageMath.sample(line: Data(#"{"type":"user","message":{}}"#.utf8)) == nil)
  }

  @Test func alertsFireOncePerLevelAndRearmAfterTheWindowRolls() {
    var state = UsageAlertPolicy.evaluate(fraction: 0.5, alerted: [])
    #expect(state.fire == nil)
    state = UsageAlertPolicy.evaluate(fraction: 0.82, alerted: state.alerted)
    #expect(state.fire == 0.80)
    state = UsageAlertPolicy.evaluate(fraction: 0.85, alerted: state.alerted)
    #expect(state.fire == nil)
    state = UsageAlertPolicy.evaluate(fraction: 0.96, alerted: state.alerted)
    #expect(state.fire == 0.95)
    state = UsageAlertPolicy.evaluate(fraction: 0.97, alerted: state.alerted)
    #expect(state.fire == nil)
    state = UsageAlertPolicy.evaluate(fraction: 0.2, alerted: state.alerted)
    #expect(state.alerted.isEmpty)
    #expect(UsageAlertPolicy.evaluate(fraction: 0.81, alerted: state.alerted).fire == 0.80)
  }

  @Test func jumpingStraightTo96FiresOnlyTheCriticalAlert() {
    let state = UsageAlertPolicy.evaluate(fraction: 0.96, alerted: [])
    #expect(state.fire == 0.95)
    #expect(state.alerted == [0.80, 0.95])
  }

  @Test func codexReportsItsOwnRateLimitPercent() throws {
    func event(_ percent: Double, reset: Double) throws -> Data {
      try JSONSerialization.data(withJSONObject: [
        "type": "event_msg",
        "payload": ["type": "token_count", "rate_limits": ["primary": ["used_percent": percent, "window_minutes": 300, "resets_at": reset]]],
      ])
    }
    let reading = try #require(AgentUsageMath.codexReading(lines: [try event(40, reset: 1_800_003_600), try event(83.5, reset: 1_800_003_600)]))
    #expect(reading.percent == 84)
    #expect(reading.resetsAt == Date(timeIntervalSince1970: 1_800_003_600))
    #expect(AgentUsageMath.codexReading(lines: [Data(#"{"payload":{"type":"token_count","info":{}}}"#.utf8)]) == nil)
  }

  @Test func ringColorEscalates() {
    #expect(AgentUsageRing.color(fraction: 0.5, base: .blue) == .blue)
    #expect(AgentUsageRing.color(fraction: 0.82, base: .blue) == .orange)
    #expect(AgentUsageRing.color(fraction: 0.96, base: .blue) == .red)
  }
}
