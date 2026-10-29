import Testing

@testable import Brim

struct LyricsParserTests {
  @Test func parsesBasicTimestamps() {
    let lyrics = LRCParser.parse("[00:12.50]Hello\n[01:02.00]World")
    #expect(lyrics.lines.count == 2)
    #expect(lyrics.lines[0].time == 12.5)
    #expect(lyrics.lines[0].text == "Hello")
    #expect(lyrics.lines[1].time == 62)
    #expect(lyrics.isSynced)
  }

  @Test func multipleTimestampsExpandAndSort() {
    let lyrics = LRCParser.parse("[00:30.00][00:10.00]Chorus\n[00:20.00]Verse")
    #expect(lyrics.lines.map(\.text) == ["Chorus", "Verse", "Chorus"])
    #expect(lyrics.lines.map(\.time) == [10, 20, 30])
  }

  @Test func offsetShiftsTimesEarlierWhenPositive() {
    let lyrics = LRCParser.parse("[offset:+500]\n[00:10.00]A")
    #expect(lyrics.lines[0].time == 9.5)
    let later = LRCParser.parse("[offset:-1000]\n[00:10.00]A")
    #expect(later.lines[0].time == 11)
  }

  @Test func ignoresMetadataAndClampsNegativeTimes() {
    let lyrics = LRCParser.parse("[ar:Artist]\n[ti:Title]\n[offset:5000]\n[00:01.00]Hi")
    #expect(lyrics.lines.count == 1)
    #expect(lyrics.lines[0].time == 0)
  }

  @Test func acceptsWholeSecondsAndThreeDigitFractions() {
    let lyrics = LRCParser.parse("[00:05]A\n[00:06.123]B\n[00:07:50]C")
    #expect(lyrics.lines.map(\.time) == [5, 6.123, 7.5])
  }

  @Test func keepsEmptyLinesAsGaps() {
    let lyrics = LRCParser.parse("[00:01.00]A\n[00:05.00]\n[00:09.00]B")
    #expect(lyrics.lines[1].text.isEmpty)
    #expect(lyrics.lines.count == 3)
  }

  @Test func parsesEnhancedWordTimes() {
    let lyrics = LRCParser.parse("[00:10.00]<00:10.00>Hello <00:10.50>big <00:11.00>world")
    let line = lyrics.lines[0]
    #expect(line.text == "Hello big world")
    #expect(line.words.map(\.text) == ["Hello ", "big ", "world"])
    #expect(line.words.map(\.time) == [10, 10.5, 11])
  }

  @Test func plainTextIsNotSynced() {
    let lyrics = LRCParser.parse("just words\nno stamps")
    #expect(lyrics.lines.isEmpty)
    #expect(!lyrics.isSynced)
  }

  @Test func handlesCRLFAndGarbage() {
    let lyrics = LRCParser.parse("\u{FEFF}[00:01.00]A\r\n[xx:yy]nope\r\n[00:02.00]B\r\n")
    #expect(lyrics.lines.map(\.text) == ["A", "B"])
  }

  @Test func hugeInputIsBounded() {
    let big = (0..<20_000).map { "[\(String(format: "%02d", $0 % 60)):00.00]x" }.joined(separator: "\n")
    #expect(LRCParser.parse(big).lines.count <= LRCParser.maxLines)
  }
}

struct LyricLookupTests {
  private let lyrics = LRCParser.parse("[00:10.00]A\n[00:20.00]B\n[00:30.00]C")

  @Test func beforeFirstLineIsNil() {
    #expect(lyrics.index(at: 0) == nil)
    #expect(lyrics.index(at: 9.99) == nil)
  }

  @Test func exactBoundaryBelongsToNewLine() {
    #expect(lyrics.index(at: 10) == 0)
    #expect(lyrics.index(at: 19.999) == 0)
    #expect(lyrics.index(at: 20) == 1)
  }

  @Test func afterLastStaysOnLast() {
    #expect(lyrics.index(at: 9_999) == 2)
  }

  @Test func emptyLyricsAndNonFiniteTime() {
    let none = LRCParser.parse("")
    #expect(none.index(at: 5) == nil)
    #expect(lyrics.index(at: .nan) == nil)
    #expect(lyrics.index(at: -4) == nil)
  }

  @Test func lookaheadAnticipatesTheNextLine() {
    #expect(lyrics.index(at: 19.9, lookahead: 0.25) == 1)
    #expect(lyrics.index(at: 19.7, lookahead: 0.25) == 0)
  }

  @Test func activeWordFollowsTime() {
    let enhanced = LRCParser.parse("[00:10.00]<00:10.00>a <00:11.00>b <00:12.00>c")
    let line = enhanced.lines[0]
    #expect(line.activeWord(at: 10.5) == 0)
    #expect(line.activeWord(at: 11) == 1)
    #expect(line.activeWord(at: 99) == 2)
    #expect(line.activeWord(at: 9) == nil)
    #expect(lyrics.lines[0].activeWord(at: 11) == nil)
  }

  @Test func windowReturnsPreviousCurrentAndNext() {
    #expect(lyrics.window(at: 25).map(\.text) == ["A", "B", "C"])
    #expect(lyrics.window(at: 5).map(\.text) == ["A"])
    #expect(lyrics.window(at: 35).map(\.text) == ["B", "C"])
  }
}
