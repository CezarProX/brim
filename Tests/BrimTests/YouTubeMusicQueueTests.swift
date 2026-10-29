import AppKit
import Foundation
import Testing

@testable import Brim

/// Node lists shaped like the YouTube Music web app's accessibility tree, as captured live on
/// 2026-10-27 (Romanian UI, the playing playlist's page open, the player page closed).
private enum Fixture {
  static func node(_ role: String, _ label: String = "", url: String = "", isOn: Bool? = nil) -> YouTubeQueueNode {
    YouTubeQueueNode(role: role, label: label, url: url, isOn: isOn)
  }

  static func watch(_ id: String) -> String { "https://music.youtube.com/watch?v=\(id)&list=PLxyz" }
  static let channel = "https://music.youtube.com/channel/UCabcdefghijklmnopqrstuv"

  /// One flattened playlist row: [play button], title link, artist links, "•", album, menu, duration, checkbox.
  static func playlistRow(_ title: String, _ artists: [String], _ duration: String, id: String,
                          button: String? = nil) -> [YouTubeQueueNode] {
    var nodes = [node("AXGroup")]
    if let button { nodes.append(node("AXButton", button)) }
    nodes.append(node("AXLink", title, url: watch(id)))
    nodes += artists.map { node("AXLink", $0, url: channel) }
    nodes += [
      node("AXStaticText", "•"), node("AXLink", "Album", url: "https://music.youtube.com/browse/MPREb_abcdefghijk"),
      node("AXGroup", "Meniu de acțiuni"), node("AXGroup"), node("AXCheckBox", "Apreciez"),
      node("AXCheckBox", "Nu apreciez"), node("AXButton", "Meniu de acțiuni"),
      node("AXGroup", "4 minute și 38 de secunde"), node("AXStaticText", duration), node("AXCheckBox"),
    ]
    return nodes
  }

  static func playerBar(shuffle: Bool = false) -> [YouTubeQueueNode] {
    [
      node("AXSlider", "Glisor"), node("AXGroup", "Now playing"), node("AXStaticText", "Leave Me Alone"),
      node("AXButton", "Michael Jackson"), node("AXGroup", "PLAYBACK_CONTROLS"),
      node("AXCheckBox", "Redă aleatoriu", isOn: shuffle), node("AXButton", "Înapoi"),
      node("AXButton", "Întrerupe"), node("AXButton", "Înainte"), node("AXStaticText", "2:14 / 4:41"),
    ]
  }

  static func playlistPage(header: String = "Întrerupe Road Trip", shuffle: Bool = false) -> [YouTubeQueueNode] {
    var nodes = [
      node("AXLink", "Acasă", url: "https://music.youtube.com/"),
      node("AXLink", "Road Trip Alex Morgan Întrerupe"), node("AXButton", "Întrerupe"),
      node("AXHeading", "Road Trip"), node("AXStaticText", "Road Trip"), node("AXButton", "Alex Morgan"),
      node("AXStaticText", "208 vizionări  •  85 de înregistrări audio  •  5 ore și 10 minute"),
      node("AXButton", "Descarcă"), node("AXButton", header), node("AXButton", "Trimite"),
      node("AXButton", "Ordonare"),
    ]
    nodes += playlistRow("Earned It (Fifty Shades Of Grey)", ["The Weeknd"], "4:38", id: "aaaaaaaaaaa",
                         button: "Redă Earned It (Fifty Shades Of Grey) - The Weeknd - 4 minute și 38 de secunde")
    nodes += playlistRow("Leave Me Alone", ["Michael Jackson"], "4:41", id: "bbbbbbbbbbb")
    nodes += playlistRow("Fancy (cu T.I. și Swizz Beatz)", ["Drake"], "5:20", id: "ccccccccccc",
                         button: "Redă Fancy - Drake - 5 minute și 20 de secunde")
    nodes += playlistRow("Zi de Zi", ["Andrei G", "Ministerul Manelelor"], "2:48", id: "ddddddddddd")
    return nodes + playerBar(shuffle: shuffle)
  }

  /// The player page's queue as Chromium is expected to flatten `ytmusic-player-queue-item`s.
  static func queueItem(_ title: String, _ byline: [String], _ duration: String, thumb: String,
                        pause: Bool = false) -> [YouTubeQueueNode] {
    [
      node("AXImage", url: "https://i.ytimg.com/vi/\(thumb)/sddefault.jpg"),
      node("AXButton", "\(pause ? "Întrerupe" : "Redă") \(title)"),
      node("AXGroup"), node("AXStaticText", title),
    ] + byline.map { node("AXStaticText", $0) } + [
      node("AXStaticText", duration), node("AXButton", "Meniu de acțiuni"),
    ]
  }

  static func queuePanel(currentPaused: Bool = true) -> [YouTubeQueueNode] {
    var nodes = [
      node("AXRadioButton", "URMEAZĂ"), node("AXStaticText", "URMEAZĂ"),
      node("AXRadioButton", "VERSURI"), node("AXStaticText", "VERSURI"),
      node("AXRadioButton", "SIMILARE"), node("AXButton", "Salvează"),
    ]
    nodes += queueItem("Earned It", ["The Weeknd"], "4:38", thumb: "aaaaaaaaaaa")
    nodes += queueItem("Leave Me Alone", ["Michael Jackson"], "4:41", thumb: "bbbbbbbbbbb", pause: currentPaused)
    nodes += queueItem("Low Life", ["Future", " & ", "The Weeknd", " • ", "EVOL"], "5:14", thumb: "eeeeeeeeeee")
    nodes += queueItem("Starboy", ["The Weeknd"], "3:50", thumb: "fffffffffff")
    return nodes
  }
}

struct YouTubeMusicQueueParsingTests {
  @Test func thePlayingPlaylistPageListsTheSongsAfterTheCurrentOne() {
    let rows = YouTubeQueueParsing.upcoming(in: Fixture.playlistPage(), title: "Leave Me Alone",
                                            artist: "Michael Jackson", limit: 12)
    #expect(rows.map(\.title) == ["Fancy (cu T.I. și Swizz Beatz)", "Zi de Zi"])
    #expect(rows.map(\.artist) == ["Drake", "Andrei G · Ministerul Manelelor"])
    #expect(rows.map(\.duration) == [320, 168])
    #expect(rows.map(\.videoID) == ["ccccccccccc", "ddddddddddd"])
  }

  @Test func aClickPressesTheRowsPlayButtonOrElseItsTitleLink() {
    let nodes = Fixture.playlistPage()
    let rows = YouTubeQueueParsing.upcoming(in: nodes, title: "Leave Me Alone", artist: "Michael Jackson", limit: 12)
    #expect(nodes[rows[0].pressIndex].label.hasPrefix("Redă Fancy"))
    #expect(nodes[rows[1].pressIndex] == Fixture.node("AXLink", "Zi de Zi", url: Fixture.watch("ddddddddddd")))
  }

  @Test func itemsCarryAThumbnailCoverAndAStableIdentity() {
    let rows = YouTubeQueueParsing.upcoming(in: Fixture.playlistPage(), title: "Leave Me Alone",
                                            artist: "Michael Jackson", limit: 1)
    let items = YouTubeQueueParsing.items(rows)
    #expect(items.count == 1)
    #expect(items[0].persistentID == "ccccccccccc")
    #expect(items[0].artworkURL == "https://i.ytimg.com/vi/ccccccccccc/mqdefault.jpg")
    #expect(items[0].index == 3)
  }

  @Test func aPlaylistPageThatIsNotPlayingOrIsShuffledIsNotTheQueue() {
    let notPlaying = Fixture.playlistPage(header: "Redă Road Trip")
    #expect(YouTubeQueueParsing.upcoming(in: notPlaying, title: "Leave Me Alone", artist: "Michael Jackson", limit: 12).isEmpty)
    let shuffled = Fixture.playlistPage(shuffle: true)
    #expect(YouTubeQueueParsing.upcoming(in: shuffled, title: "Leave Me Alone", artist: "Michael Jackson", limit: 12).isEmpty)
  }

  @Test func aSongMissingFromThePageGivesAnEmptyList() {
    #expect(YouTubeQueueParsing.upcoming(in: Fixture.playlistPage(), title: "Blinding Lights", artist: "The Weeknd",
                                         limit: 12).isEmpty)
    #expect(YouTubeQueueParsing.upcoming(in: [], title: "Leave Me Alone", artist: "", limit: 12).isEmpty)
  }

  @Test func theUpNextPanelWinsAndStartsAfterThePlayingItem() {
    let nodes = Fixture.playlistPage().dropLast(Fixture.playerBar().count) + Fixture.queuePanel() + Fixture.playerBar()
    let rows = YouTubeQueueParsing.upcoming(in: Array(nodes), title: "Leave Me Alone", artist: "Michael Jackson", limit: 12)
    #expect(rows.map(\.title) == ["Low Life", "Starboy"])
    // Byline runs are joined and the part after "•" is dropped.
    #expect(rows[0].artist == "Future & The Weeknd")
    #expect(rows[0].videoID == "eeeeeeeeeee")
    #expect(rows[0].artworkURL == "https://i.ytimg.com/vi/eeeeeeeeeee/sddefault.jpg")
    #expect(Array(nodes)[rows[0].pressIndex].label == "Redă Low Life")
  }

  @Test func withoutAPauseButtonThePanelFindsTheSongByTitle() {
    let nodes = Fixture.queuePanel(currentPaused: false) + Fixture.playerBar()
    let rows = YouTubeQueueParsing.upcoming(in: nodes, title: "Leave Me Alone", artist: "Michael Jackson", limit: 1)
    #expect(rows.map(\.title) == ["Low Life"])
  }

  @Test func theTabLabelsBeforeTheFirstItemAreNeverATitle() {
    let nodes = Fixture.queuePanel() + Fixture.playerBar()
    guard let range = YouTubeQueueParsing.queueRange(nodes) else { Issue.record("no queue range"); return }
    #expect(YouTubeQueueParsing.rows(in: nodes, range: range).map(\.title) == ["Earned It", "Leave Me Alone", "Low Life", "Starboy"])
  }

  @Test func featuredArtistSuffixesStillMatchTheSong() {
    let row = YouTubeQueueRow(title: "Fancy (cu T.I. și Swizz Beatz)", artist: "Drake", duration: 1, videoID: nil,
                              artworkURL: nil, position: 1, pressIndex: 0, isPlaying: false)
    #expect(YouTubeQueueParsing.sameSong(row, title: "Fancy", artist: "Drake"))
    #expect(YouTubeQueueParsing.sameSong(row, title: "FANCY", artist: ""))
    #expect(!YouTubeQueueParsing.sameSong(row, title: "Fancy", artist: "The Weeknd"))
    #expect(!YouTubeQueueParsing.sameSong(row, title: "Fan", artist: "Drake"))
  }

  @Test func durationsAndThumbnailsAreParsedStrictly() {
    #expect(YouTubeQueueParsing.durationSeconds("4:38") == 278)
    #expect(YouTubeQueueParsing.durationSeconds("1:02:03") == 3723)
    #expect(YouTubeQueueParsing.durationSeconds("2:14 / 4:41") == nil)
    #expect(YouTubeQueueParsing.durationSeconds("193 K") == nil)
    #expect(YouTubeQueueParsing.videoID(fromThumbnail: "https://i.ytimg.com/vi/abcdefghijk/mqdefault.jpg") == "abcdefghijk")
    #expect(YouTubeQueueParsing.videoID(fromThumbnail: "https://evil.example/vi/abcdefghijk/x.jpg") == nil)
  }
}

struct YouTubeMusicBrowserQueueTests {
  private let json = """
    [{"t":"Earned It","a":"The Weeknd","d":"4:38","i":"https://i.ytimg.com/vi/aaaaaaaaaaa/sddefault.jpg","s":false},
     {"t":"Leave Me Alone","a":"Michael Jackson","d":"4:41","i":"","s":true},
     {"t":"","a":"x","d":"1:00","i":"","s":false},
     {"t":"Low Life","a":"Future • EVOL","d":"5:14","i":"https://evil.example/a.jpg","s":false}]
    """.replacingOccurrences(of: "\n", with: "")

  @Test func browserRowsFollowTheSelectedItem() {
    let rows = YouTubeQueueParsing.browserUpcoming("null\n" + json + "\n", title: "Leave Me Alone", artist: "", limit: 12)
    #expect(rows.map(\.title) == ["Low Life"])
    #expect(rows[0].artist == "Future")
    #expect(rows[0].artworkURL == nil)
    // The page index of the item, so the click script finds it even after skipped rows.
    #expect(rows[0].position == 4)
    #expect(rows[0].pressIndex == 3)
  }

  @Test func aClosedQueueTakesCoversFromTheSameSongsOnThePage() {
    let lazy = "data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP"
    let page = """
    [{"t":"Now","a":"A","d":"3:00","i":"\(lazy)","s":true,"v":"","p":""},
     {"t":"Black and Yellow","a":"Wiz Khalifa","d":"3:38","i":"\(lazy)","s":false,"v":"O7_hvm34Obo","p":""},
     {"t":"Upload.mp3","a":"Me","d":"2:00","i":"\(lazy)","s":false,"v":"","p":"https://lh3.googleusercontent.com/abc=w60"},
     {"t":"Unknown","a":"B","d":"2:00","i":"\(lazy)","s":false,"v":"not-an-id","p":"https://evil.example/x.jpg"}]
    """.replacingOccurrences(of: "\n", with: "")
    let rows = YouTubeQueueParsing.browserUpcoming(page, title: "Now", artist: "A", limit: 12)
    let items = YouTubeQueueParsing.items(rows)
    #expect(items[0].artworkURL == "https://i.ytimg.com/vi/O7_hvm34Obo/mqdefault.jpg", "a watch link's video id")
    #expect(items[1].artworkURL == "https://lh3.googleusercontent.com/abc=w60", "an upload's loaded picture")
    #expect(items[2].artworkURL == nil, "bad ids and foreign hosts are ignored")
  }

  @Test func malformedBrowserOutputReadsAsEmpty() {
    #expect(YouTubeQueueParsing.browserRows("not json").isEmpty)
    #expect(YouTubeQueueParsing.browserUpcoming("", title: "S", artist: "A", limit: 12).isEmpty)
  }

  @Test func pageScriptsEmbedInAppleScriptAndNeverInlinePageText() throws {
    #expect(!YouTubeMusicQueueReader.browserReadScript.contains("\""))
    #expect(!YouTubeMusicQueueReader.browserReadScript.contains("\\"))
    let hostile = QueueItem(index: 2, persistentID: "x", title: "a'); alert(1); ('\" \\", artist: "", duration: 1)
    let current = NowPlayingSnapshot(source: .youtubeChrome, title: "Now", artist: "", album: "", duration: 1,
                                     position: 0, isPlaying: true)
    let script = try YouTubeMusicQueueReader.browserPlayScript(item: hostile, current: current)
    #expect(!script.contains("alert"))
    #expect(!script.contains("\""))
    #expect(!script.contains("\\"))
    #expect(script.contains("items[1]"))
  }

  nonisolated private static let chromeInstalled =
    NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome") != nil

  @Test(.enabled(if: chromeInstalled)) func chromeTabScriptCompiles() {
    let source = YouTubeMusicQueueReader.browserScript(for: .youtubeChrome, javaScript: YouTubeMusicQueueReader.browserReadScript)
    var error: NSDictionary?
    let compiled = NSAppleScript(source: source)?.compileAndReturnError(&error) ?? false
    #expect(compiled, "\(error?[NSAppleScript.errorMessage] ?? "")")
  }

  /// "Every window/tab" must carry a real absolute-ordinal selector: a null one made Chrome answer
  /// -1700, so the queue was never read from the page (seen live).
  @Test func everyElementSpecifierHasAnAllOrdinal() {
    let specifier = NowPlayingBrowser.all("cwin")
    let selector = specifier.forKeyword(NowPlayingAppleEvents.code("seld"))
    #expect(selector?.descriptorType == NowPlayingAppleEvents.code("abso"))
    #expect(selector?.typeCodeValue == NowPlayingAppleEvents.code("all "))
  }

  @Test func safariTabScriptCompiles() {
    let source = YouTubeMusicQueueReader.browserScript(for: .youtubeSafari, javaScript: YouTubeMusicQueueReader.browserReadScript)
    var error: NSDictionary?
    let compiled = NSAppleScript(source: source)?.compileAndReturnError(&error) ?? false
    #expect(compiled, "\(error?[NSAppleScript.errorMessage] ?? "")")
  }
}

@MainActor
struct YouTubeMusicQueueModelTests {
  private func track(_ source: NowPlayingSource, _ title: String = "Leave Me Alone") -> NowPlayingTrack {
    NowPlayingTrack(snapshot: NowPlayingSnapshot(source: source, title: title, artist: "Michael Jackson", album: "",
                                                 duration: 281, position: 10, isPlaying: true), artwork: nil)
  }

  private func settle(_ condition: () -> Bool) async {
    for _ in 0..<50 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
  }

  @Test func youTubeSongsUseTheYouTubeBackendAndClicksReachIt() async {
    var played: [String] = []
    let item = QueueItem(index: 3, persistentID: "ccccccccccc", title: "Fancy", artist: "Drake", duration: 320)
    let next = QueueItem(index: 4, persistentID: "ddddddddddd", title: "Zi de Zi", artist: "Andrei G", duration: 168)
    let youtube = QueueBackend(read: { snapshot, _ in snapshot.title == "Leave Me Alone" ? [item, next] : [] },
                               play: { item, snapshot in played.append("\(item.title)<-\(snapshot.title)") },
                               artwork: { _ in nil }, retriesWhenEmpty: true)
    let music = QueueBackend(read: { _, _ in Issue.record("Apple Music was read for a YouTube song"); return [] },
                             play: { _, _ in }, artwork: { _ in nil })
    let model = PlayingNextModel(music: music, youtube: youtube)
    model.refresh(for: track(.youtubeApp))
    await settle { !model.items.isEmpty }
    #expect(model.items.map(\.title) == ["Fancy", "Zi de Zi"])
    model.playNow(next, track: track(.youtubeApp))
    #expect(model.items.map(\.title) == ["Zi de Zi", "Fancy"])
    await settle { !played.isEmpty }
    #expect(played == ["Zi de Zi<-Leave Me Alone"])
  }

  @Test func anEmptyYouTubeReadIsRetriedForTheSameSong() async {
    var reads = 0
    let youtube = QueueBackend(read: { _, _ in reads += 1; return [] }, play: { _, _ in }, artwork: { _ in nil },
                               retriesWhenEmpty: true)
    let model = PlayingNextModel(music: youtube, youtube: youtube)
    model.refresh(for: track(.youtubeChrome))
    await settle { reads == 1 && !model.isLoading }
    model.refresh(for: track(.youtubeChrome))
    await settle { reads == 2 }
    #expect(reads == 2)
    #expect(model.items.isEmpty)
    #expect(!model.isUnavailable)
  }

  @Test func aFailingYouTubeReadShowsTheEmptyState() async {
    let youtube = QueueBackend(read: { _, _ in throw NowPlayingFailure.accessibility }, play: { _, _ in },
                               artwork: { _ in nil }, retriesWhenEmpty: true)
    let model = PlayingNextModel(music: youtube, youtube: youtube)
    model.refresh(for: track(.youtubeApp))
    await settle { model.isUnavailable }
    #expect(model.isUnavailable)
    #expect(model.items.isEmpty)
    #expect(!model.isLoading)
  }

  @Test func fixtureModelsAnswerYouTubeSongsWithoutReadingThePage() async {
    let model = PlayingNextModel(read: { _ in "2\u{1F}i\u{1F}Next\u{1F}Art\u{1F}10" }, perform: { _ in "" })
    model.refresh(for: track(.youtubeApp))
    await settle { !model.items.isEmpty }
    #expect(model.items.map(\.title) == ["Next"])
  }

  @Test func youTubeSourcesOfferAQueueButSpotifyDoesNot() {
    for source in [NowPlayingSource.music, .youtubeApp, .youtubeChrome, .youtubeSafari] {
      #expect(QueueCapability.supportsQueue(source))
    }
    #expect(!QueueCapability.supportsQueue(.spotify))
    #expect(!QueueCapability.supportsQueue(nil))
  }
}

@Test func browserReadScriptTakesCoversFromThePagesOwnRowData() throws {
  let script = YouTubeMusicQueueReader.browserReadScript
  #expect(!script.contains("\""), "no double quotes")
  #expect(!script.contains("\\"), "no backslashes")
  #expect(script.contains("deep[index]"))
  #expect(script.contains("trustedTypes.createPolicy"), "the page only runs scripts made through Trusted Types")
  let main = try #require(script.components(separatedBy: "atob('").dropFirst().first?.components(separatedBy: "')").first)
  let decoded = try #require(Data(base64Encoded: main).flatMap { String(data: $0, encoding: .utf8) })
  #expect(decoded == YouTubeMusicQueueReader.mainWorldQueue)
  #expect(decoded.contains("thumbnail.thumbnails") && decoded.contains("videoId"))
}

