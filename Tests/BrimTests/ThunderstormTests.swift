import Foundation
import Testing

@testable import Brim

@Suite struct ThunderstormRankingTests {
  private let now = Date(timeIntervalSince1970: 2_000_000_000)

  @Test func exactBeatsPrefixBeatsWordBeatsSubstringBeatsFuzzy() {
    let exact = ThunderFuzzy.score(query: "safari", in: "Safari")
    let prefix = ThunderFuzzy.score(query: "saf", in: "Safari")
    let word = ThunderFuzzy.score(query: "code", in: "Visual Studio Code")
    let inside = ThunderFuzzy.score(query: "tud", in: "Visual Studio Code")
    let fuzzy = ThunderFuzzy.score(query: "vsc", in: "Visual Studio Code")
    #expect(exact! > prefix!)
    #expect(prefix! > word!)
    #expect(word! > inside!)
    #expect(inside! > fuzzy!)
  }

  @Test func nonMatchesReturnNil() {
    #expect(ThunderFuzzy.score(query: "xyz", in: "Safari") == nil)
    #expect(ThunderFuzzy.score(query: "", in: "Safari") == nil)
  }

  @Test func fuzzyNeedsLettersInOrder() {
    #expect(ThunderFuzzy.score(query: "fsa", in: "Safari") == nil)
    #expect(ThunderFuzzy.score(query: "sfr", in: "Safari") != nil)
  }

  @Test func frecencyLiftsAFrequentlyUsedMatch() {
    let candidates = [ThunderCandidate(id: "a", title: "Notes"), ThunderCandidate(id: "b", title: "Notion")]
    let plain = ThunderRanking.rank(candidates, query: "not", frecency: [:], now: now)
    let used = ThunderRanking.rank(
      candidates, query: "not", frecency: ["b": ThunderFrecency(count: 12, lastUsed: now)], now: now)
    #expect(plain.first?.id == "a")  // shorter title wins on equal prefix match
    #expect(used.first?.id == "b")
  }

  @Test func frecencyDecaysWithAge() {
    let fresh = ThunderFrecency(count: 5, lastUsed: now).bonus(now: now)
    let old = ThunderFrecency(count: 5, lastUsed: now.addingTimeInterval(-60 * 86_400)).bonus(now: now)
    #expect(old < fresh / 10)
  }

  @Test func emptyQueryShowsOnlyUsedItemsMostUsedFirst() {
    let candidates = [
      ThunderCandidate(id: "a", title: "A"), ThunderCandidate(id: "b", title: "B"), ThunderCandidate(id: "c", title: "C"),
    ]
    let table = [
      "b": ThunderFrecency(count: 9, lastUsed: now), "c": ThunderFrecency(count: 2, lastUsed: now),
    ]
    #expect(ThunderRanking.rank(candidates, query: "", frecency: table, now: now).map(\.id) == ["b", "c"])
  }

  @Test func keywordMatchesCountLessThanTitleMatches() {
    let candidates = [
      ThunderCandidate(id: "kw", title: "Zed", keywords: "editor code"),
      ThunderCandidate(id: "title", title: "Code"),
    ]
    #expect(ThunderRanking.rank(candidates, query: "code", frecency: [:], now: now).first?.id == "title")
  }

  @Test func recordingKeepsTheTableBounded() {
    var table: [String: ThunderFrecency] = [:]
    for index in 0..<450 {
      table = ThunderFrecency.recording("id\(index)", in: table, now: now.addingTimeInterval(Double(index)))
    }
    #expect(table.count == 400)
    #expect(table["id449"] != nil)
    #expect(table["id0"] == nil)
  }
}

@Suite struct ThunderCalculatorTests {
  @Test func evaluatesPrecedenceAndParentheses() {
    #expect(ThunderCalculator.evaluate("2 + 3 * 4") == 14)
    #expect(ThunderCalculator.evaluate("(2 + 3) * 4") == 20)
    #expect(ThunderCalculator.evaluate("2 ^ 3 ^ 2") == 512)
    #expect(ThunderCalculator.evaluate("-4 + 10") == 6)
    #expect(ThunderCalculator.evaluate("10 / 4") == 2.5)
  }

  @Test func supportsPercentFunctionsAndConstants() {
    #expect(ThunderCalculator.evaluate("20% of 150") == 30)
    #expect(ThunderCalculator.evaluate("50%") == 0.5)
    #expect(ThunderCalculator.evaluate("sqrt(81)") == 9)
    #expect(abs((ThunderCalculator.evaluate("2 * pi") ?? 0) - 2 * Double.pi) < 1e-9)
    #expect(ThunderCalculator.evaluate("1,000 + 1") == 1001)
    #expect(ThunderCalculator.evaluate("3 × 4 ÷ 2") == 6)
  }

  @Test func rejectsNonsenseAndUnsafeInput() {
    #expect(ThunderCalculator.evaluate("safari") == nil)
    #expect(ThunderCalculator.evaluate("42") == nil)  // a bare number is not a calculation
    #expect(ThunderCalculator.evaluate("1/0") == nil)
    #expect(ThunderCalculator.evaluate("2 +") == nil)
    #expect(ThunderCalculator.evaluate("sqrt(-1)") == nil)
    #expect(ThunderCalculator.evaluate("system(\"rm\")") == nil)
    #expect(ThunderCalculator.evaluate(String(repeating: "(", count: 500) + "1" + String(repeating: ")", count: 500)) == nil)
    #expect(ThunderCalculator.evaluate("9^9^9^9") == nil)
  }

  @Test func formatsWithoutTrailingZeros() {
    let us = Locale(identifier: "en_US")
    #expect(ThunderCalculator.format(2.5, locale: us) == "2.5")
    #expect(ThunderCalculator.format(1_234_567, locale: us) == "1,234,567")
    #expect(ThunderCalculator.format(0.1 + 0.2, locale: us) == "0.3")
  }
}

@Suite struct ThunderUnitTests {
  @Test func convertsLengthMassAndData() throws {
    #expect(abs(try #require(ThunderUnits.convert("10 km to mi")).result - 6.2137) < 0.001)
    #expect(abs(try #require(ThunderUnits.convert("1 kg in lb")).result - 2.20462) < 0.001)
    #expect(try #require(ThunderUnits.convert("2 gb to mb")).result == 2000)
  }

  @Test func convertsTemperatureWithOffsets() throws {
    #expect(abs(try #require(ThunderUnits.convert("100 c to f")).result - 212) < 1e-9)
    #expect(abs(try #require(ThunderUnits.convert("32 f to c")).result) < 1e-9)
    #expect(abs(try #require(ThunderUnits.convert("0 c to k")).result - 273.15) < 1e-9)
  }

  @Test func refusesMixedDimensionsAndUnknownUnits() {
    #expect(ThunderUnits.convert("5 kg to km") == nil)
    #expect(ThunderUnits.convert("5 foo to bar") == nil)
    #expect(ThunderUnits.convert("hello") == nil)
  }
}

@Suite struct ThunderResultsTests {
  private func sources() -> ThunderSources {
    var s = ThunderSources()
    s.apps = [
      InstalledApp(name: "Safari", url: URL(fileURLWithPath: "/Applications/Safari.app"), bundleID: "com.apple.Safari"),
      InstalledApp(name: "Slack", url: URL(fileURLWithPath: "/Applications/Slack.app"), bundleID: "com.tinyspeck.slackmacgap"),
    ]
    s.systemCommands = ThunderSystemCommand.allCases
    s.quicklinks = ThunderQuicklink.samples
    return s
  }

  @Test func calculatorAnswersComeFirst() {
    let rows = ThunderResults.build(query: "2+2*3", sources: sources())
    #expect(rows.first?.kind == .calculator)
    #expect(rows.first?.title == "8")
    #expect(rows.last?.kind == .web)
  }

  @Test func quicklinkExpandsItsQuery() {
    let rows = ThunderResults.build(query: "gh swift testing", sources: sources())
    let link = rows.first { $0.kind == .quicklink }
    #expect(link?.action == .open(URL(string: "https://github.com/search?q=swift%20testing")!))
  }

  @Test func appsRankByNameAndWebIsAlwaysLast() {
    let rows = ThunderResults.build(query: "saf", sources: sources())
    #expect(rows.first?.title == "Safari")
    #expect(rows.last?.kind == .web)
  }

  @Test func emptyTrashNeedsConfirmationAndIsFindable() {
    let rows = ThunderResults.build(query: "empty trash", sources: sources())
    let trash = rows.first { $0.id == "sys:emptyTrash" }
    #expect(trash != nil)
    #expect(ThunderSystemCommand.emptyTrash.needsConfirmation)
    #expect(!ThunderSystemCommand.lockScreen.needsConfirmation)
  }

  @Test func snippetsExpandPlaceholders() {
    var s = sources()
    s.snippets = [ThunderSnippet(keyword: ";sig", title: "Signature", text: "Best, Alex {clipboard}")]
    s.clipboardText = "(copied)"
    let rows = ThunderResults.build(query: "signature", sources: s)
    #expect(rows.first?.action == .paste("Best, Alex (copied)"))
  }

  @Test func clipboardHistoryIsSearchedFromTwoCharacters() {
    var s = sources()
    s.clipboard = [
      ClipboardEntry(id: UUID(), date: .now, kind: .text, text: "invoice number 4471", fingerprint: "f", byteCount: 10, pixelSize: nil)
    ]
    #expect(ThunderResults.build(query: "invoice", sources: s).contains { $0.kind == .clipboard })
    #expect(!ThunderResults.build(query: "i", sources: s).contains { $0.kind == .clipboard })
  }

  @Test func quicklinksRefuseDangerousSchemes() {
    #expect(ThunderQuicklink.expand("javascript:alert({query})", query: "x") == nil)
    #expect(ThunderQuicklink.expand("file:///etc/passwd", query: "x") == nil)
    #expect(ThunderQuicklink.expand("https://example.com/?q={query}", query: "a&b=c")?.absoluteString == "https://example.com/?q=a%26b%3Dc")
  }
}

@Suite struct ThunderstormExtraTests {
  @Test func percentOfWorksInsideALongerExpression() {
    #expect(ThunderCalculator.evaluate("12 * (3 + 4) + 20% of 50") == 94)
    #expect(ThunderCalculator.evaluate("10% of (200 + 50)") == 25)
  }

  @Test func fileResultsSkipDeveloperNoise() {
    #expect(!ThunderFileSearch.isUserVisible("/Users/me/go/pkg/mod/x/trash.go"))
    #expect(!ThunderFileSearch.isUserVisible("/Users/me/proj/venv/lib/x.py"))
    #expect(!ThunderFileSearch.isUserVisible("/Users/me/Library/Caches/x"))
    #expect(!ThunderFileSearch.isUserVisible("/Users/me/.config/x"))
    #expect(ThunderFileSearch.isUserVisible("/Users/me/Documents/report.pdf"))
  }
}
