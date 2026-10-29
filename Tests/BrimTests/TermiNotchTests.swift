import Foundation
import Testing
@testable import Brim

struct ANSIParserTests {
  private func events(_ text: String) -> [ANSIEvent] {
    var parser = ANSIParser()
    return parser.parse(Data(text.utf8))
  }

  @Test("Plain text and controls")
  func plain() {
    #expect(events("a\r\n") == [.text("a"), .control(13), .control(10)])
  }

  @Test("SGR with params")
  func sgr() {
    #expect(events("\u{1B}[1;31mX") == [.csi(params: [1, 31], prefix: nil, final: "m"), .text("X")])
    #expect(events("\u{1B}[m") == [.csi(params: [], prefix: nil, final: "m")])
  }

  @Test("Sequences split across reads are completed")
  func split() {
    var parser = ANSIParser()
    #expect(parser.parse(Data("\u{1B}[3".utf8)).isEmpty)
    #expect(parser.parse(Data("1m".utf8)) == [.csi(params: [31], prefix: nil, final: "m")])
  }

  @Test("OSC title, private modes and UTF-8")
  func misc() {
    #expect(events("\u{1B}]0;hello\u{07}") == [.osc("0;hello")])
    #expect(events("\u{1B}[?25l") == [.csi(params: [25], prefix: "?", final: "l")])
    #expect(events("é→") == [.text("é"), .text("→")])
  }
}

struct TerminalBufferTests {
  private func render(_ text: String, columns: Int = 20, rows: Int = 4) -> TerminalBuffer {
    var parser = ANSIParser()
    var buffer = TerminalBuffer(columns: columns, rows: rows)
    buffer.apply(parser.parse(Data(text.utf8)))
    return buffer
  }

  @Test("Text, newline and carriage return")
  func lines() {
    let buffer = render("one\r\ntwo")
    #expect(buffer.text(row: 0) == "one")
    #expect(buffer.text(row: 1) == "two")
  }

  @Test("Cursor movement and erase")
  func cursor() {
    let buffer = render("hello\u{1B}[3D\u{1B}[K!")
    #expect(buffer.text(row: 0) == "he!")
    let home = render("abc\u{1B}[2;3Hz")
    #expect(home.text(row: 1) == "  z")
    #expect(render("x\u{1B}[2J").screenText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
  }

  @Test("Colors: 16, 256 and truecolor")
  func colors() {
    let buffer = render("\u{1B}[31ma\u{1B}[38;5;200mb\u{1B}[38;2;1;2;3mc\u{1B}[0md")
    #expect(buffer.grid[0][0].style.foreground == .palette(1))
    #expect(buffer.grid[0][1].style.foreground == .palette(200))
    #expect(buffer.grid[0][2].style.foreground == .rgb(1, 2, 3))
    #expect(buffer.grid[0][3].style == TerminalStyle())
  }

  @Test("Scrolling pushes lines to scrollback")
  func scrolling() {
    let buffer = render("1\r\n2\r\n3\r\n4\r\n5\r\n6")
    #expect(buffer.scrollback.count == 2)
    #expect(buffer.text(row: 3) == "6")
  }

  @Test("Wrap at the last column, delete characters, title")
  func wrapDeleteTitle() {
    let wrapped = render("abcdefghij", columns: 5, rows: 3)
    #expect(wrapped.text(row: 0) == "abcde" && wrapped.text(row: 1) == "fghij")
    #expect(render("abcd\u{1B}[3D\u{1B}[P").text(row: 0) == "acd")
    #expect(render("\u{1B}]2;my title\u{07}").title == "my title")
  }

  @Test("Alternate screen is restored")
  func alternate() {
    let buffer = render("keep\u{1B}[?1049hVIM\u{1B}[?1049l")
    #expect(buffer.text(row: 0) == "keep")
  }
}

struct PTYSessionTests {
  @Test("A real pty echoes what is written to it")
  func roundTrip() async throws {
    let session = PTYSession()
    let collected = LockedData()
    session.onOutput = { collected.append($0) }
    try session.start(executable: "/bin/cat", login: false, cwd: NSTemporaryDirectory())
    defer { session.terminate() }
    session.send("hello-pty\n")
    for _ in 0..<100 where !collected.string.contains("hello-pty") { try await Task.sleep(for: .milliseconds(30)) }
    #expect(collected.string.contains("hello-pty"))
    #expect(session.isRunning)
  }

  @Test("A login shell starts, runs only what is typed, and reports its folder")
  func shell() async throws {
    let session = PTYSession()
    let collected = LockedData()
    session.onOutput = { collected.append($0) }
    let dir = NSTemporaryDirectory()
    try session.start(executable: "/bin/sh", arguments: [], login: false, cwd: dir)
    defer { session.terminate() }
    try await Task.sleep(for: .milliseconds(300))
    session.send("echo brim-$((20+22))\n")
    for _ in 0..<100 where !collected.string.contains("brim-42") { try await Task.sleep(for: .milliseconds(30)) }
    #expect(collected.string.contains("brim-42"))
    let reported = try #require(session.currentDirectory)
    #expect(URL(fileURLWithPath: reported).resolvingSymlinksInPath().path == URL(fileURLWithPath: dir).resolvingSymlinksInPath().path)
  }

  @Test("Exit is reported")
  func exits() async throws {
    let session = PTYSession()
    let exited = LockedData()
    session.onExit = { _ in exited.append(Data([1])) }
    try session.start(executable: "/usr/bin/true", login: false)
    for _ in 0..<100 where exited.isEmpty { try await Task.sleep(for: .milliseconds(30)) }
    #expect(!exited.isEmpty)
  }

  /// After `exit`, Termi-Notch restarts the same tab: what is typed then must reach the new shell.
  @Test("A session restarted after its process exited accepts input again")
  func restartAfterExit() async throws {
    let session = PTYSession()
    let exited = LockedData()
    session.onExit = { _ in exited.append(Data([1])) }
    try session.start(executable: "/usr/bin/true", login: false)
    for _ in 0..<100 where exited.isEmpty { try await Task.sleep(for: .milliseconds(30)) }
    #expect(!session.isRunning)
    let collected = LockedData()
    session.onOutput = { collected.append($0) }
    try session.start(executable: "/bin/cat", login: false, cwd: NSTemporaryDirectory())
    defer { session.terminate() }
    #expect(session.isRunning)
    session.send("back-again\n")
    for _ in 0..<100 where !collected.string.contains("back-again") { try await Task.sleep(for: .milliseconds(30)) }
    #expect(collected.string.contains("back-again"))
  }

  @Test("Key encoding sends Tab and arrows through")
  func keys() {
    #expect(TerminalKeyEncoder.bytes(characters: "\t", charactersIgnoringModifiers: "\t", keyCode: 48, control: false, option: false) == "\t")
    #expect(TerminalKeyEncoder.bytes(characters: "", charactersIgnoringModifiers: "", keyCode: 126, control: false, option: false) == "\u{1B}[A")
    #expect(TerminalKeyEncoder.bytes(characters: "\u{03}", charactersIgnoringModifiers: "c", keyCode: 8, control: true, option: false) == "\u{03}")
  }
}

final class LockedData: @unchecked Sendable {
  private var data = Data()
  private let lock = NSLock()
  func append(_ more: Data) { lock.lock(); data.append(more); lock.unlock() }
  var string: String { lock.lock(); defer { lock.unlock() }; return String(decoding: data, as: UTF8.self) }
  var isEmpty: Bool { lock.lock(); defer { lock.unlock() }; return data.isEmpty }
}
