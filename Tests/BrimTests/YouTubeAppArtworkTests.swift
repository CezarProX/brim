import Foundation
import Testing

@testable import Brim

struct YouTubeAppArtworkTests {
  @Test func scriptEmbedsInAppleScriptAndChecksTheSong() throws {
    let script = try YouTubeAppArtwork.script(title: "Say \"Hi\" \\ now')")
    #expect(!script.contains("\""))
    #expect(!script.contains("\\"))
    #expect(!script.contains("Hi"), "the title travels base64-encoded")
    #expect(script.contains("navigator.mediaSession"))
    #expect(script.contains("location.hostname !== 'music.youtube.com'"))
  }

  @Test func coverCopyKeepsEveryOtherField() {
    var sample = NowPlayingSnapshot(source: .youtubeApp, title: "Come Thru", artist: "Drake", album: "NWTS",
                                    duration: 200, position: 12, isPlaying: true, albumURL: "https://music.youtube.com/browse/MPREb_x",
                                    isFavorite: true, isShuffling: false)
    sample.pageURL = "https://music.youtube.com/playlist?list=PL1"
    sample.playbackRate = 0
    let copy = sample.withArtworkURL("https://yt3.googleusercontent.com/abc")
    #expect(copy.artworkURL == "https://yt3.googleusercontent.com/abc")
    #expect(copy.withArtworkURL(nil) == sample, "only the cover differs")
    #expect(copy.pageURL == sample.pageURL && copy.playbackRate == 0 && copy.isFavorite == true)
  }
}
