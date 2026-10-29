import AppKit
import SwiftUI
import Testing

@testable import Brim

// MARK: - Termi-Notch

@MainActor
@Suite("Termi-Notch app")
struct TermiNotchAppTests {
  @Test func pasteNeverContainsReturn() {
    #expect(TerminalPaste.payload("ls -la\n", bracketed: false) == "ls -la")
    #expect(TerminalPaste.payload("cd x\r\nls\r\n", bracketed: false) == "cd x; ls")
    #expect(!TerminalPaste.payload("a\nb\nc", bracketed: false).contains("\r"))
    let bracketed = TerminalPaste.payload("a\nb", bracketed: true)
    #expect(bracketed == "\u{1B}[200~a\nb\u{1B}[201~")
    #expect(!bracketed.contains("\r"))
  }

  @Test func bufferTracksBracketedPasteAndFreshness() {
    var parser = ANSIParser()
    var buffer = TerminalBuffer(columns: 40, rows: 4)
    buffer.apply(parser.parse(Data("% ".utf8)))
    #expect(buffer.isFresh)
    buffer.apply(parser.parse(Data("\u{1B}[?2004h".utf8)))
    #expect(buffer.bracketedPaste)
    buffer.apply(parser.parse(Data("ls\r\nfile\r\n% ".utf8)))
    #expect(!buffer.isFresh)
    #expect(buffer.fullText == "% ls\nfile\n%")
  }

  @Test func clearOutputDropsScrollback() {
    let session = TerminalSession(columns: 20, rows: 2)
    session.showPreview("1\r\n2\r\n3\r\n4\r\n5")
    #expect(session.outputText.contains("1"))
    session.clearOutput()
    #expect(!session.outputText.contains("1"))
  }

  /// Runs a real login shell through the PTY: typed text only runs after Return.
  @Test func realShellRunsOnlyAfterReturn() async throws {
    let session = TerminalSession(directory: NSTemporaryDirectory(), columns: 80, rows: 10)
    session.start()
    defer { session.stop() }
    #expect(session.isAlive)
    try await Task.sleep(for: .seconds(2))
    session.insertWithoutRunning("echo QS_MARKER_$((20+22))")
    try await Task.sleep(for: .seconds(1))
    #expect(!session.outputText.contains("QS_MARKER_42"))
    session.send("\r")
    var seen = false
    for _ in 0..<30 where !seen {
      try await Task.sleep(for: .milliseconds(200))
      seen = session.outputText.contains("QS_MARKER_42")
    }
    #expect(seen, "output was: \(session.outputText)")
  }
}

// MARK: - Teleprompter

@MainActor
@Suite("Teleprompter app")
struct TeleprompterAppTests {
  @Test func sampleScriptHasWordsAndDoesNotPlayWhenEmpty() {
    let model = TeleprompterModel(settings: DropletRender.isolatedSettings())
    #expect(TeleprompterMath.wordCount(TeleprompterModel.sampleScript) > 30)
    model.play()
    #expect(!model.isPlaying)
    model.script = TeleprompterModel.sampleScript
    model.play()
    #expect(model.isPlaying)
    model.pause()
    model.setFontSize(100)
    #expect(model.fontSize == 48)
  }
}

// MARK: - Xcode Builds

@MainActor
@Suite("Xcode Builds app")
struct XcodeBuildsAppTests {
  private func entry(_ title: String, status: String?, errors: Int = 0, warnings: Int = 0, stopped: TimeInterval) -> XcodeManifestEntry {
    XcodeManifestEntry(
      fileName: "\(stopped).xcactivitylog", title: title, started: Date(timeIntervalSinceNow: stopped - 60),
      stopped: Date(timeIntervalSinceNow: stopped), status: status, errors: errors, warnings: warnings)
  }

  @Test func lastBuildIsTheNewestFinishedBuild() {
    let snapshot = XcodeLogSnapshot(
      project: "Demo", latestLog: nil, latestLogModified: nil,
      entries: [
        entry("Build Demo", status: "S", stopped: -3600),
        entry("Run Demo", status: "S", stopped: -10),
        entry("Build Demo", status: "E", errors: 2, stopped: -600),
      ], xcodebuildRunning: false)
    let last = XcodeBuildDetector.lastBuild(snapshot)
    #expect(last?.project == "Demo")
    #expect(last?.succeeded == false)
    #expect(last?.errors == 2)
    #expect(last?.duration == 60)
  }

  @Test func modelKeepsLastBuildAfterTheLiveResultExpires() {
    let model = XcodeBuildModel()
    let snapshot = XcodeLogSnapshot(
      project: "Demo", latestLog: "a.xcactivitylog", latestLogModified: Date(timeIntervalSinceNow: -7200),
      entries: [entry("Build Demo", status: "S", warnings: 1, stopped: -7200)], xcodebuildRunning: false)
    model.apply(snapshot)
    #expect(model.status == .idle)
    #expect(model.last?.succeeded == true)
    #expect(model.scanned)
    let text = XcodeBuildCard.summary(last: model.last!)
    #expect(text.contains("1m 00s") && text.contains("1 warning"))
  }

  @Test func settingsSummaryWording() {
    #expect(XcodeBuildCard.summary(for: .failed(project: "A", duration: 5, errors: 1)) == "After 5s · 1 error")
  }
}

// MARK: - Agents

@MainActor
@Suite("Agents app")
struct AgentsAppTests {
  @Test func detectionSummary() {
    #expect(AgentDetection.summary(followed: [.claude, .codex], installed: [.claude]) == "Following: Claude Code")
    #expect(AgentDetection.summary(followed: [], installed: [.claude]).contains("switched off"))
    #expect(AgentDetection.summary(followed: [.claude], installed: []).contains("No coding agents"))
  }

  @Test func detectionUsesFolders() throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("qs-home-\(UUID())")
    try FileManager.default.createDirectory(at: home.appendingPathComponent(".codex/sessions"), withIntermediateDirectories: true)
    #expect(AgentDetection.isInstalled(.codex, home: home))
    #expect(!AgentDetection.isInstalled(.claude, home: home))
  }

  @Test func stepHeadlineDropsTheDoubledVerb() {
    #expect(CodingAgentParser.headline(for: "Running Read the stream client's seek") == "Read the stream client's seek")
    #expect(CodingAgentParser.headline(for: "Running swift test") == "Running swift test")
    #expect(CodingAgentParser.headline(for: "Reading Model.swift") == "Reading Model.swift")
    #expect(CodingAgentParser.headline(for: "Running ") == "Running ")
  }

  @Test func pageHugsTheHub() {
    #expect(AgentsHubHeightKey.pageHeight(content: nil, chrome: 70, cap: 322) == 322)
    #expect(AgentsHubHeightKey.pageHeight(content: 150.2, chrome: 70, cap: 322) == 221)
    #expect(AgentsHubHeightKey.pageHeight(content: 400, chrome: 70, cap: 322) == 322)
  }

  @Test func sessionTitlePrefersTheRename() {
    func line(_ json: String) -> Data { Data(json.utf8) }
    let generated = line(#"{"type":"ai-title","aiTitle":"Agent tab în Dynamic Island","sessionId":"a"}"#)
    let renamed = line(#"{"type":"custom-title","customTitle":"SONG PANEL","sessionId":"a"}"#)
    let chat = line(#"{"type":"user","message":{"content":"ai-title is just text here"}}"#)
    #expect(CodingAgentParser.title(lines: [generated, chat]) == "Agent tab în Dynamic Island")
    #expect(CodingAgentParser.title(lines: [renamed, generated]) == "SONG PANEL")
    #expect(CodingAgentParser.title(lines: [chat]) == nil)
    #expect(CodingAgentParser.title(lines: [line(#"{"type":"custom-title","customTitle":"  "}"#), generated]) == "Agent tab în Dynamic Island")
  }

  /// What this Mac really has right now (printed, not asserted).
  @Test func readsRealSessionsOnThisMac() {
    let sessions = CodingAgentModel.readAll()
    let installed = CodingAgentSession.Tool.allCases.filter { AgentDetection.isInstalled($0) }
    print("AGENTS installed:", installed.map(\.rawValue), "live sessions:", sessions.map { "\($0.tool.rawValue)/\($0.project ?? "-")/\($0.title ?? "-")/\($0.statusText)" })
    #expect(sessions.count <= CodingAgentModel.maxSessions * 2)
  }
}

// MARK: - Renders

@MainActor
@Suite("Island apps renders: terminal, prompter, Xcode, agents", .serialized)
struct TermiTeleXcodeAgentsRenderTests {
  private let size = CGSize(width: 560, height: 236)

  private func shell<V: View>(_ title: String, _ view: V) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 10) {
        Image(systemName: "chevron.left").frame(width: 26, height: 26).background(IslandFill.raised, in: Circle())
        Text(title).font(IslandFont.title)
      }.frame(height: 28)
      view.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
    .padding(.horizontal, 28).padding(.top, 8).padding(.bottom, 20)
    .foregroundStyle(IslandInk.primary)
  }

  @Test func termi() async throws {
    let model = TermiNotchModel(settings: DropletRender.isolatedSettings())
    let fresh = TerminalSession(directory: "/Users/demo", columns: 70, rows: 6)
    fresh.showPreview("demo@mac ~ % ")
    model.adopt(fresh)
    try await DropletRender.png(shell("Termi-Notch", TermiNotchIslandView(model: model)), size: CGSize(width: 616, height: 316), name: "apps-termi-notch-first-run.png", background: .black)
    let busy = TerminalSession(directory: "/Users/demo", columns: 70, rows: 8)
    busy.showPreview("demo@mac ~ % ls\r\n\u{1B}[34mDesktop\u{1B}[0m  \u{1B}[34mDocuments\u{1B}[0m  Package.swift\r\ndemo@mac ~ % ")
    let model2 = TermiNotchModel(settings: DropletRender.isolatedSettings())
    model2.adopt(busy)
    try await DropletRender.png(shell("Termi-Notch", TermiNotchIslandView(model: model2)), size: CGSize(width: 616, height: 316), name: "apps-termi-notch-output.png", background: .black)
  }

  @Test func teleprompter() async throws {
    let shared = TeleprompterModel.shared
    let saved = shared.script
    defer { shared.script = saved }
    shared.script = ""
    try await DropletRender.png(shell("Teleprompter", TeleprompterIslandView()), size: CGSize(width: 616, height: 306), name: "apps-teleprompter-empty.png", background: .black)
    shared.script = TeleprompterModel.sampleScript
    try await DropletRender.png(shell("Teleprompter", TeleprompterIslandView()), size: CGSize(width: 616, height: 306), name: "apps-teleprompter-script.png", background: .black)
  }

  @Test func xcode() async throws {
    let model = XcodeBuildModel()
    let card = { shell("Xcode Builds", XcodeBuildCard(model: model)) }
    let s = CGSize(width: 616, height: 206)
    model.preview(.idle, watching: false)
    try await DropletRender.png(card(), size: s, name: "apps-xcode-off.png", background: .black)
    model.preview(.idle, found: false)
    try await DropletRender.png(card(), size: s, name: "apps-xcode-nothing-yet.png", background: .black)
    model.preview(.idle, last: XcodeLastBuild(project: "Brim", succeeded: true, errors: 0, warnings: 2, duration: 65, finished: .now.addingTimeInterval(-300)))
    try await DropletRender.png(card(), size: s, name: "apps-xcode-last-build.png", background: .black)
    model.preview(.building(project: "Brim", since: .now.addingTimeInterval(-47)))
    try await DropletRender.png(card(), size: s, name: "apps-xcode-building.png", background: .black)
    model.preview(.idle, last: XcodeLastBuild(project: "Brim", succeeded: false, errors: 3, warnings: 0, duration: 12, finished: .now.addingTimeInterval(-90)))
    try await DropletRender.png(card(), size: s, name: "apps-xcode-last-failed.png", background: .black)
  }

  private func session(_ tool: CodingAgentSession.Tool, _ state: CodingAgentSession.State) -> CodingAgentSession {
    CodingAgentSession(
      tool: tool, model: "Opus 5.5", state: state, steps: ["Edit Model.swift", "Read shot.png", "Bash: swift test"],
      lastMessage: "Fixed the failing test and re-ran the suite.", outputTokens: 18_400, contextTokens: 90_000, turns: 6,
      started: .now.addingTimeInterval(-540), updated: .now, id: "/tmp/\(tool.rawValue).jsonl", project: "screenshot app")
  }

  @Test func agents() async throws {
    let coding = CodingAgentModel()
    let status = AgentActivityModel()
    let s = CGSize(width: 616, height: 322)
    let view = { shell("Agents", AgentsHubView(coding: coding, status: status)) }
    try await DropletRender.png(view(), size: s, name: "apps-agents-idle.png", background: .black)
    coding.setSessionsForPreview([session(.claude, .running("Edit Model.swift")), session(.codex, .waiting)])
    try await DropletRender.png(view(), size: s, name: "apps-agents-live.png", background: .black)
    coding.setSessionsForPreview([session(.claude, .needsInput("Approve: Bash swift test"))])
    try await DropletRender.png(view(), size: s, name: "apps-agents-attention.png", background: .black)
    // The island's real page: narrower and shorter, a busy Claude session next to another one.
    var busy = session(.claude, .running("Running Read the stream client's seek and send"))
    busy = CodingAgentSession(
      tool: .claude, model: "Opus 5.5", state: busy.state,
      steps: ["Running Read the stream client's seek and send", "Running Read Apple Events commands and helper", "Finding files"],
      lastMessage: "Good point. I'll check every place a command can go through.", outputTokens: 36_200, contextTokens: 46_000,
      turns: 1, started: .now.addingTimeInterval(-1079), updated: .now, id: "/tmp/busy.jsonl", project: "screenshot app")
    busy.linesAdded = 17
    busy.linesRemoved = 2
    coding.setSessionsForPreview([busy])
    try await DropletRender.png(view(), size: s, name: "apps-agents-busy.png", background: .black)
    // What the island now sizes to: the hub's own height plus the back row, instead of a fixed 322.
    let measured = NSHostingView(rootView: AgentsHubView(coding: coding, status: status).frame(width: s.width - 56))
    let fitted = AgentsHubHeightKey.pageHeight(content: measured.fittingSize.height, chrome: 70, cap: s.height)
    #expect(fitted < s.height)
    try await DropletRender.png(view(), size: CGSize(width: s.width, height: fitted), name: "apps-agents-busy-fitted.png", background: .black)
    var api = session(.codex, .running("Running swift build"))
    api.project = "brim-site"
    api.id = "/tmp/api.jsonl"
    busy.title = "Agent tab în Dynamic Island"
    var song = session(.claude, .waiting)
    song.id = "/tmp/song.jsonl"
    song.title = "SONG PANEL"
    coding.setSessionsForPreview([busy, song, api])
    coding.select(busy.id)
    try await DropletRender.png(view(), size: s, name: "apps-agents-busy-three.png", background: .black)
  }
}
