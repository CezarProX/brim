import Foundation
import Testing

@testable import Brim

struct LyricsMotionTests {
  private let words = [LyricWord(time: 10, text: "aa "), LyricWord(time: 11, text: "bb "), LyricWord(time: 12, text: "cc")]

  // MARK: Word fill

  @Test func wordsFillGraduallyInOrder() {
    #expect(LyricWordSynth.fills(of: words, lineEnd: 13, at: 9) == [0, 0, 0])
    #expect(LyricWordSynth.fills(of: words, lineEnd: 13, at: 10.5) == [0.5, 0, 0])
    #expect(LyricWordSynth.fills(of: words, lineEnd: 13, at: 11.25) == [1, 0.25, 0])
    #expect(LyricWordSynth.fills(of: words, lineEnd: 13, at: 14) == [1, 1, 1])
  }

  @Test func fillsSurviveBadInput() {
    #expect(LyricWordSynth.fills(of: [], lineEnd: 1, at: 1).isEmpty)
    #expect(LyricWordSynth.fills(of: words, lineEnd: 13, at: .nan) == [0, 0, 0])
    let stacked = [LyricWord(time: 5, text: "a"), LyricWord(time: 5, text: "b")]
    #expect(LyricWordSynth.fills(of: stacked, lineEnd: 5, at: 5.01).allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 1 })
  }

  @Test func sweepEndFollowsTheSungSpan() {
    let lyrics = LRCParser.parse("[00:01.00]Hello there world\n[00:05.00]Second line\n[00:09.00]")
    let end = lyrics.sweepEnd(at: 0)
    #expect(end > 1 && end < 5, "plain lines finish before the next stamp")
    #expect(lyrics.sweepEnd(at: 2) > 9, "the last line still gets a span")
    #expect(lyrics.sweepEnd(at: 9) == 0)
  }

  // MARK: Held words

  @Test func lastWordIsHeldUntilNearTheNextLine() {
    let lyrics = LRCParser.parse("[00:10.00]And I will always love you\n[00:18.00]Next")
    let last = try! #require(lyrics.sweepWords(at: 0).last)
    let end = lyrics.sweepEnd(at: 0)
    #expect(last.time - 10 < 4, "the words keep a sung pace")
    #expect(end - last.time > 2.5, "the last word stretches instead of finishing early")
    #expect(end < 18, "and still finishes before the next line")
  }

  @Test func aLineThatFillsItsGapSpreadsAcrossIt() {
    let lyrics = LRCParser.parse("[00:10.00]Hello darkness my old friend\n[00:13.00]Next")
    let words = lyrics.sweepWords(at: 0)
    #expect(lyrics.sweepEnd(at: 0) > 12.6 && lyrics.sweepEnd(at: 0) < 13)
    #expect(words[words.count - 1].time > 11.8, "the words spread over the whole line")
  }

  @Test func holdIsCappedBeforeAnInstrumental() {
    let lyrics = LRCParser.parse("[00:10.00]Oh yeah\n[01:00.00]Next")
    #expect(lyrics.sweepEnd(at: 0) - 10 <= LyricWordSynth.maxHoldSeconds + 3)
  }

  // MARK: Column

  @Test func rowsStackWithSpacing() {
    #expect(LyricsColumnMath.tops(heights: [10, 20, 30], spacing: 5) == [0, 15, 40])
  }

  @Test func focusInterpolatesBetweenRowCentres() {
    let heights: [CGFloat] = [10, 20, 30]
    let tops = LyricsColumnMath.tops(heights: heights, spacing: 5)
    #expect(LyricsColumnMath.focusY(tops: tops, heights: heights, position: 0) == 5)
    #expect(LyricsColumnMath.focusY(tops: tops, heights: heights, position: 1) == 25)
    #expect(LyricsColumnMath.focusY(tops: tops, heights: heights, position: 0.5) == 15)
    #expect(LyricsColumnMath.focusY(tops: tops, heights: heights, position: 7) == 55, "clamped to the last row")
    #expect(LyricsColumnMath.focusY(tops: [], heights: [], position: 0) == 0)
  }

  @Test func rowsBelowTrailWhileAStepIsInFlight() {
    // Stepping from line 3 to 4, halfway there.
    #expect(LyricsColumnMath.lagged(position: 3.5, row: 2, step: 0.1) == 3.5, "rows above lead")
    #expect(LyricsColumnMath.lagged(position: 3.5, row: 4, step: 0.1) == 3.5, "the new line leads")
    let next = LyricsColumnMath.lagged(position: 3.5, row: 5, step: 0.1)
    let later = LyricsColumnMath.lagged(position: 3.5, row: 6, step: 0.1)
    #expect(next < 3.5 && later < next && later >= 3)
    #expect(LyricsColumnMath.lagged(position: 4, row: 9, step: 0.1) == 4, "at rest every row agrees")
    #expect(LyricsColumnMath.lagged(position: 3.5, row: 6, step: 0) == 3.5, "no cascade with reduce motion")
  }
}
