import Foundation
import Testing

@testable import Brim

struct AMLLLyricsTests {
  static let ttml = """
    <tt xmlns="http://www.w3.org/ns/ttml" xmlns:ttm="http://www.w3.org/ns/ttml#metadata" xmlns:itunes="http://music.apple.com/lyric-ttml-internal" itunes:timing="Word"><head></head>\
    <body dur="3:14.571"><div begin="27.173" end="3:14.571">\
    <p begin="27.173" end="28.516"><span begin="27.173" end="27.407">I&apos;ve</span> <span begin="27.407" end="27.510">been</span> \
    <span begin="27.899" end="28.516">call</span><span ttm:role="x-translation" xml:lang="zh-CN">我</span></p>\
    <p begin="1:05.494" end="1:06.899"><span begin="1:05.494" end="1:06.175">May</span><span begin="1:06.175" end="1:06.899">be</span>\
    <span ttm:role="x-bg"><span begin="1:06.2" end="1:06.5">(oh)</span></span></p>\
    </div></body></tt>
    """

  // MARK: TTML

  @Test func ttmlBecomesWordTimedLines() throws {
    let converted = try #require(TTMLLyrics.enhancedLRC(from: Self.ttml))
    let lyrics = LRCParser.parse(converted)
    #expect(lyrics.lines.count == 2)
    let first = lyrics.lines[0]
    #expect(first.text == "I've been call", "translations are dropped")
    #expect(first.words.map(\.text) == ["I've ", "been ", "call"])
    #expect(abs(first.words[2].time - 27.899) < 0.001)
    #expect(abs((first.end ?? 0) - 28.516) < 0.001, "the line keeps its real end")
    let second = lyrics.lines[1]
    #expect(second.text == "Maybe", "syllables join into one word; background vocals are skipped")
    #expect(second.words.map(\.text) == ["May", "be"])
    #expect(abs(second.time - 65.494) < 0.001)
    #expect(abs((TTMLLyrics.duration(of: Self.ttml) ?? 0) - 194.571) < 0.001)
  }

  @Test func ttmlRejectsJunk() {
    #expect(TTMLLyrics.enhancedLRC(from: "") == nil)
    #expect(TTMLLyrics.enhancedLRC(from: "<tt><body></body></tt>") == nil)
    #expect(TTMLLyrics.enhancedLRC(from: "not xml <<<") == nil)
    #expect(TTMLLyrics.seconds("12.5") == 12.5)
    #expect(TTMLLyrics.seconds("1:02.25") == 62.25)
    #expect(TTMLLyrics.seconds("1:00:01") == 3601)
    #expect(TTMLLyrics.seconds("4.2s") == 4.2)
    #expect(TTMLLyrics.seconds("x") == nil)
  }

  @Test func lineEndSurvivesTheLRCRoundTrip() {
    let lyrics = LRCParser.parse("[00:01.000]<00:01.000>a <00:01.500>b<00:02.250>\n[00:03.00]plain")
    #expect(lyrics.lines[0].end == 2.25)
    #expect(lyrics.lines[0].words.count == 2)
    #expect(lyrics.lines[1].end == nil)
    #expect(lyrics.sweepEnd(at: 0) == 2.25)
  }

  // MARK: Matching

  private func item(_ id: Int, _ title: String, _ artists: [String]) -> AMLLLyrics.Item {
    AMLLLyrics.Item(id: id, musicNames: [title], artistNames: artists)
  }

  @Test func candidatesNeedTitleAndArtist() {
    let items = [item(1, "Heartbeat", ["Cloudier"]), item(2, "Blinding Lights", ["The Weeknd"]),
                 item(3, "Blinding Lights (Remix)", ["Someone Else"])]
    let picked = AMLLLyrics.candidates(items, title: "Blinding Lights", artist: "The Weeknd")
    #expect(picked.map(\.id) == [2])
    #expect(AMLLLyrics.candidates(items, title: "Blinding Lights - Single", artist: "The Weeknd & Daft Punk").map(\.id) == [2])
    #expect(AMLLLyrics.candidates(items, title: "Heartbeat", artist: "Someone").isEmpty)
  }

  @Test func normalizationDropsDecorations() {
    #expect(AMLLLyrics.normalized("BIRDS OF A FEATHER") == AMLLLyrics.normalized("Birds of a Feather"))
    #expect(AMLLLyrics.normalized("Levitating (feat. DaBaby)") == "levitating")
    #expect(AMLLLyrics.normalized("Espresso - Single") == "espresso")
  }

  @Test func lookupVerifiesDurationAndFallsBackToNil() async {
    let search = #"{"status":200,"data":{"items":[{"id":7,"musicNames":["Blinding Lights"],"artistNames":["The Weeknd"]}]}}"#
    let body = try! JSONSerialization.data(withJSONObject: ["status": 200, "data": ["id": 7, "lyrics": Self.ttml]])
    let fetch: @Sendable (URL) async throws -> Data = { url in
      url.path.hasSuffix("/search") ? Data(search.utf8) : body
    }
    let query = LyricsProvider.Query(title: "Blinding Lights", artist: "The Weeknd", album: "", duration: 194)
    #expect(await AMLLLyrics.lookup(query, fetch: fetch) != nil)
    let wrongLength = LyricsProvider.Query(title: "Blinding Lights", artist: "The Weeknd", album: "", duration: 150)
    #expect(await AMLLLyrics.lookup(wrongLength, fetch: fetch) == nil, "lyrics longer than the track belong to another version")
    #expect(await AMLLLyrics.lookup(query, fetch: { _ in throw URLError(.timedOut) }) == nil)
  }
}
