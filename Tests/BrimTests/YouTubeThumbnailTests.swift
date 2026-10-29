import AppKit
import Testing

@testable import Brim

struct YouTubeThumbnailTests {
  @Test func readsTheVideoIDFromTheWatchPage() {
    #expect(YouTubeThumbnail.videoID(from: "https://music.youtube.com/watch?v=--gehIjpUmY&list=RDAMVM") == "--gehIjpUmY")
    #expect(YouTubeThumbnail.videoID(from: "https://music.youtube.com/browse/MPREb_x") == nil)
    #expect(YouTubeThumbnail.videoID(from: "https://evil.example/watch?v=--gehIjpUmY") == nil)
    #expect(YouTubeThumbnail.videoID(from: "https://music.youtube.com/watch?v=short") == nil)
  }

  @Test func buildsAnAllowedArtworkURL() throws {
    let url = try #require(YouTubeThumbnail.artworkURL(videoID: "--gehIjpUmY"))
    #expect(url == "https://i.ytimg.com/vi/--gehIjpUmY/maxresdefault.jpg")
    #expect(NowPlayingSnapshot.safeArtworkURL(url) != nil)
  }

  @Test func accessibilitySnapshotFallsBackToTheVideoThumbnail() throws {
    let nodes = [
      NowPlayingAccessibility.PlayerText(role: "AXButton", label: "Previous", url: ""),
      NowPlayingAccessibility.PlayerText(role: "AXButton", label: "Pause", url: ""),
      NowPlayingAccessibility.PlayerText(role: "AXButton", label: "Next", url: ""),
      NowPlayingAccessibility.PlayerText(role: "AXHeading", label: "Sistemul de vara (Live)", url: ""),
    ]
    let snapshot = try #require(NowPlayingAccessibility.snapshot(
      from: nodes, pageURL: "https://music.youtube.com/watch?v=--gehIjpUmY&list=R"))
    #expect(snapshot.artworkURL == "https://i.ytimg.com/vi/--gehIjpUmY/maxresdefault.jpg")
  }

  @Test func artistComesFromTheBylineWhenChromeHidesTheChannelLinks() throws {
    typealias Text = NowPlayingAccessibility.PlayerText
    let nodes = [
      Text(role: "AXButton", label: "Previous"), Text(role: "AXButton", label: "Pause"),
      Text(role: "AXButton", label: "Next"), Text(role: "AXHeading", label: "Euforia"),
      Text(role: "AXStaticText", label: "Euforia"),
      Text(role: "AXStaticText", label: "Calinacho & Mario Fresh • Ai Grijă • 2024"),
    ]
    let snapshot = try #require(NowPlayingAccessibility.snapshot(from: nodes))
    #expect(snapshot.artist == "Calinacho & Mario Fresh")
  }

  @Test func cropsLetterboxedThumbnailsToTheCenteredSquare() throws {
    #expect(YouTubeThumbnail.squareCrop(width: 1280, height: 720) == CGRect(x: 280, y: 0, width: 720, height: 720))
    // 4:3 thumbnails carry black bars around a 16:9 picture.
    #expect(YouTubeThumbnail.squareCrop(width: 480, height: 360) == CGRect(x: 105, y: 45, width: 270, height: 270))
  }
}
