import Foundation
import SQLite3
import Testing

@testable import Brim

struct NotificationExtractionTests {
  private let apps: Set<String> = ["Messages", "Slack", "Mail"]
  private func isApp(_ s: String) -> Bool { apps.contains(s) }

  private func text(_ s: String) -> AXNodeSnapshot { AXNodeSnapshot(role: "AXStaticText", value: s) }

  @Test func readsTitleAndBodyWithAppFromGroupDescription() {
    let tree = AXNodeSnapshot(role: "AXWindow", children: [
      AXNodeSnapshot(role: "AXGroup", descriptionText: "Messages, Anna, See you at 8", children: [
        AXNodeSnapshot(role: "AXGroup", children: [text("Anna"), text("See you at 8?"), text("now")]),
        AXNodeSnapshot(role: "AXButton", descriptionText: "Close", children: [text("Close")]),
      ])
    ])
    let c = NotificationBannerExtractor.content(from: tree, isAppName: isApp)
    #expect(c?.appName == "Messages")
    #expect(c?.title == "Anna")
    #expect(c?.body == "See you at 8?")
    #expect(c?.subtitle == "")
  }

  @Test func appLabelAsFirstTextAndSubtitle() {
    let tree = AXNodeSnapshot(role: "AXWindow", children: [
      AXNodeSnapshot(role: "AXGroup", children: [text("Slack"), text("#design"), text("Maya"), text("ship it"), text("2m ago")])
    ])
    let c = NotificationBannerExtractor.content(from: tree, isAppName: isApp)
    #expect(c?.appName == "Slack")
    #expect(c?.title == "#design")
    #expect(c?.subtitle == "Maya")
    #expect(c?.body == "ship it")
  }

  @Test func fallsBackToDescriptionWhenValueEmpty() {
    let tree = AXNodeSnapshot(role: "AXGroup", children: [
      text("Mail"), AXNodeSnapshot(role: "AXStaticText", descriptionText: "Invoice paid"), text("Thanks!")])
    let c = NotificationBannerExtractor.content(from: tree, isAppName: isApp)
    #expect(c?.title == "Invoice paid")
    #expect(c?.body == "Thanks!")
  }

  @Test func rejectsTreesWithoutAKnownApp() {
    let tree = AXNodeSnapshot(role: "AXGroup", children: [text("Hello"), text("World")])
    #expect(NotificationBannerExtractor.content(from: tree, isAppName: isApp) == nil)
  }

  @Test func boundedDepthIgnoresDeepText() {
    var node = text("buried")
    for _ in 0..<(NotificationBannerExtractor.maxDepth + 3) { node = AXNodeSnapshot(role: "AXGroup", children: [node]) }
    let tree = AXNodeSnapshot(role: "AXGroup", children: [text("Slack"), text("Hi"), node])
    #expect(NotificationBannerExtractor.content(from: tree, isAppName: isApp)?.body == "Hi")
  }
}

struct NotificationPolicyTests {
  private func item(_ body: String = "b", app: String = "Slack", id: String? = nil) -> NotificationContent {
    NotificationContent(bundleID: id, appName: app, title: "t", body: body)
  }

  @Test func dedupesWithinTwoSecondsOnly() {
    var deduper = NotificationDeduper()
    let t0 = Date()
    let first = deduper.accept(item(), now: t0)
    let repeated = deduper.accept(item(), now: t0.addingTimeInterval(1.9))
    let later = deduper.accept(item(), now: t0.addingTimeInterval(4))
    let different = deduper.accept(item("other"), now: t0.addingTimeInterval(4.1))
    #expect(first && !repeated && later && different)
  }

  @Test func queueShowsFirstAndPromotesNext() {
    var q = NotificationQueue().enqueued(item("1")).enqueued(item("2")).enqueued(item("3"))
    #expect(q.current?.body == "1")
    #expect(q.overflow == 2)
    q = q.dismissed()
    #expect(q.current?.body == "2")
    #expect(q.dismissed().dismissed().current == nil)
  }

  @Test func queueCapsPendingKeepingNewest() {
    var q = NotificationQueue()
    for i in 0..<20 { q = q.enqueued(item("\(i)")) }
    #expect(q.overflow == NotificationQueue.maxPending)
    #expect(q.pending.last?.body == "19")
  }

  @Test func filterDenyBeatsAllowAndMatchesNameOrBundle() {
    let f = NotificationFilter(denied: ["com.apple.mail"], allowed: ["Slack", "Mail"])
    #expect(f.permits(bundleID: "com.tinyspeck.slackmacgap", appName: "Slack"))
    #expect(!f.permits(bundleID: "com.apple.mail", appName: "Mail"))
    #expect(!f.permits(bundleID: "com.apple.Notes", appName: "Notes"))
    #expect(NotificationFilter().permits(bundleID: nil, appName: "Anything"))
  }

  @Test func timeLabels() {
    let now = Date()
    #expect(NotificationTimeLabel.text(for: now, now: now) == "now")
    #expect(NotificationTimeLabel.text(for: now.addingTimeInterval(-300), now: now) == "5m ago")
    #expect(NotificationTimeLabel.text(for: now.addingTimeInterval(-7200), now: now) == "2h ago")
  }

  @Test func onlyMessagesSupportsReply() {
    #expect(NotificationContent(bundleID: NotificationApps.messages, appName: "Messages", title: "Anna").supportsReply)
    #expect(!NotificationContent(bundleID: "com.apple.mail", appName: "Mail", title: "Anna").supportsReply)
  }
}

struct UsernotedParsingTests {
  static func fixturePlist() throws -> Data {
    let root: [String: Any] = [
      "app": "com.apple.MobileSMS", "date": 770_000_000.0,
      "req": ["titl": "Anna", "subt": "", "body": "Dinner at 8?", "iden": "x"],
    ]
    return try PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0)
  }

  @Test func parsesBinaryPlist() throws {
    let c = try #require(UsernotedPlist.parse(try Self.fixturePlist()))
    #expect(c.bundleID == "com.apple.MobileSMS")
    #expect(c.title == "Anna")
    #expect(c.body == "Dinner at 8?")
    #expect(c.date == Date(timeIntervalSinceReferenceDate: 770_000_000))
  }

  @Test func rejectsGarbageAndEmpty() throws {
    #expect(UsernotedPlist.parse(Data([1, 2, 3])) == nil)
    let empty = try PropertyListSerialization.data(fromPropertyList: ["req": [String: String]()], format: .binary, options: 0)
    #expect(UsernotedPlist.parse(empty) == nil)
  }

  @Test func queriesRowsAfterHighWaterMark() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("qs-fixture-\(UUID().uuidString).db")
    defer { try? FileManager.default.removeItem(at: url) }
    var db: OpaquePointer?
    #expect(sqlite3_open(url.path, &db) == SQLITE_OK)
    sqlite3_exec(db, "CREATE TABLE app(app_id INTEGER PRIMARY KEY, identifier TEXT); CREATE TABLE record(rec_id INTEGER PRIMARY KEY, app_id INTEGER, data BLOB); INSERT INTO app VALUES(1,'com.apple.MobileSMS');", nil, nil, nil)
    let blob = try Self.fixturePlist()
    for id in [5, 6] {
      var st: OpaquePointer?
      sqlite3_prepare_v2(db, "INSERT INTO record VALUES(?,1,?)", -1, &st, nil)
      sqlite3_bind_int(st, 1, Int32(id))
      _ = blob.withUnsafeBytes { sqlite3_bind_blob(st, 2, $0.baseAddress, Int32(blob.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
      sqlite3_step(st); sqlite3_finalize(st)
    }
    sqlite3_close(db)
    let rows = try UsernotedReader.query(database: url, after: 5)
    #expect(rows.map(\.recID) == [6])
    #expect(rows.first?.bundleID == "com.apple.MobileSMS")
    #expect(UsernotedPlist.parse(rows[0].data, fallbackBundleID: rows[0].bundleID)?.body == "Dinner at 8?")
  }
}

struct MessagesReplyEscapingTests {
  private let nasty = [#"He said "hi" \ back"#, "line1\nline2", "-e tell app \"Finder\" to quit", "'; do shell script \"touch /tmp/x\" --", "emoji 😀 é"]
  private let echo = ["on run argv", "return (item 1 of argv) & \"|\" & (item 2 of argv)", "end run"]

  @Test func scriptSourceNeverContainsUserText() {
    for text in nasty {
      let args = MessagesReply.arguments(recipient: "Anna", text: text)
      let sources = stride(from: 1, to: args.count - 3, by: 2).map { args[$0] }
      #expect(!sources.contains { $0.contains(text) })
      #expect(args.suffix(3) == ["--", "Anna", text])
    }
  }

  @Test func osascriptReturnsArgumentsVerbatim() {
    for text in nasty {
      let result = MessagesReply.runCapturing(arguments: MessagesReply.arguments(recipient: "A \"B\"", text: text, lines: echo))
      #expect(result == .success("A \"B\"|" + text.trimmingCharacters(in: .newlines)))
    }
  }
}
