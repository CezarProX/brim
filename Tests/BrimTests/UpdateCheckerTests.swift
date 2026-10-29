import Foundation
import Testing

@testable import Brim

struct UpdateModelsTests {
  @Test func comparesVersions() throws {
    let a = try #require(SemanticVersion("1.2.3"))
    #expect(a < SemanticVersion("1.10.0")!)
    #expect(SemanticVersion("v2.0")! > a)
    #expect(SemanticVersion("1.2")! == SemanticVersion("1.2.0")!)
    #expect(SemanticVersion("1.0.0-beta.1")! < SemanticVersion("1.0.0")!)
    #expect(SemanticVersion("1.0.0+45")! == SemanticVersion("1.0.0")!)
    #expect(SemanticVersion("banana") == nil)
    #expect(SemanticVersion("") == nil)
  }

  @Test func onlyHTTPSFeedsAreAccepted() {
    #expect(UpdateFeed.validatedURL("https://example.com/feed.json") != nil)
    #expect(UpdateFeed.validatedURL("http://example.com/feed.json") == nil)
    #expect(UpdateFeed.validatedURL("file:///etc/passwd") == nil)
    #expect(UpdateFeed.validatedURL("   ") == nil)
    #expect(UpdateFeed.validatedURL("https://") == nil)
  }

  @Test func parsesSimpleJSON() throws {
    let json = #"{"version":"1.4.0","notes":"Faster","url":"https://example.com/Brim.dmg"}"#
    let release = try #require(UpdateFeed.parse(Data(json.utf8)))
    #expect(release.version == "1.4.0")
    #expect(release.notes == "Faster")
    #expect(release.downloadURL?.absoluteString == "https://example.com/Brim.dmg")
  }

  @Test func parsesGitHubReleaseAndPrefersAsset() throws {
    let json = """
      {"tag_name":"v2.1.0","body":"Notes","html_url":"https://github.com/o/r/releases/tag/v2.1.0",
       "assets":[{"browser_download_url":"https://github.com/o/r/releases/download/v2.1.0/App.dmg"}]}
      """
    let release = try #require(UpdateFeed.parse(Data(json.utf8)))
    #expect(release.version == "v2.1.0")
    #expect(release.downloadURL?.lastPathComponent == "App.dmg")
  }

  @Test func insecureDownloadLinkIsDropped() throws {
    let json = #"{"version":"2.0.0","url":"http://evil.example/App.dmg"}"#
    #expect(try #require(UpdateFeed.parse(Data(json.utf8))).downloadURL == nil)
  }

  @Test func parsesFirstAppcastItem() throws {
    let xml = """
      <?xml version="1.0"?><rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel>
      <item><title>New</title><description><![CDATA[<p>Big <b>release</b></p>]]></description>
      <enclosure url="https://example.com/QS-3.0.dmg" sparkle:shortVersionString="3.0.0" sparkle:version="30"/></item>
      <item><enclosure url="https://example.com/QS-2.0.dmg" sparkle:shortVersionString="2.0.0"/></item>
      </channel></rss>
      """
    let release = try #require(UpdateFeed.parse(Data(xml.utf8)))
    #expect(release.version == "3.0.0")
    #expect(release.notes == "Big release")
    #expect(release.downloadURL?.lastPathComponent == "QS-3.0.dmg")
  }

  @Test func garbageDoesNotParse() {
    #expect(UpdateFeed.parse(Data("not a feed".utf8)) == nil)
    #expect(UpdateFeed.parse(Data(#"{"version":"abc"}"#.utf8)) == nil)
  }

  @Test func decisionComparesAgainstCurrent() {
    let newer = UpdateRelease(version: "1.1.0", notes: "", downloadURL: nil)
    #expect(UpdateDecision.decide(current: "1.0.0", release: newer) == .available(newer))
    #expect(UpdateDecision.decide(current: "1.1.0", release: newer) == .upToDate(current: "1.1.0"))
    #expect(UpdateDecision.decide(current: "2.0.0", release: newer) == .upToDate(current: "2.0.0"))
  }
}

@MainActor
struct UpdateCheckerTests {
  private func fetching(_ text: String) -> UpdateChecker.Fetch { { _ in Data(text.utf8) } }

  @Test func emptyFeedIsNotConfiguredAndNeverFetches() async {
    let outcome = await UpdateChecker.shared.check(feed: "  ", current: "1.0.0") { _ in
      Issue.record("must not fetch")
      return Data()
    }
    #expect(outcome == .notConfigured)
  }

  @Test func rejectsNonHTTPSWithoutFetching() async {
    let outcome = await UpdateChecker.shared.check(feed: "http://example.com/f.json", current: "1.0.0") { _ in
      Issue.record("must not fetch")
      return Data()
    }
    #expect(outcome == .invalidFeed)
  }

  @Test func reportsAvailableAndUpToDate() async {
    let feed = #"{"version":"1.5.0","notes":"n"}"#
    let newer = await UpdateChecker.shared.check(feed: "https://e.com/f", current: "1.0.0", fetch: fetching(feed))
    guard case .available(let release) = newer else { Issue.record("expected available"); return }
    #expect(release.version == "1.5.0")
    let same = await UpdateChecker.shared.check(feed: "https://e.com/f", current: "1.5.0", fetch: fetching(feed))
    #expect(same == .upToDate(current: "1.5.0"))
  }

  @Test func reportsUnreadableFeedAndNetworkErrors() async {
    let bad = await UpdateChecker.shared.check(feed: "https://e.com/f", current: "1.0.0", fetch: fetching("nope"))
    guard case .failed = bad else { Issue.record("expected failed"); return }
    let offline = await UpdateChecker.shared.check(feed: "https://e.com/f", current: "1.0.0") { _ in
      throw URLError(.notConnectedToInternet)
    }
    guard case .failed = offline else { Issue.record("expected failed"); return }
  }
}
