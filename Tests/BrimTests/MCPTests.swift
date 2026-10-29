import Foundation
import Testing

@testable import Brim

struct MCPServerCoreTests {
  private func json(_ text: String?) throws -> [String: Any] {
    let line = try #require(text)
    let object = try JSONSerialization.jsonObject(with: Data(line.utf8))
    return try #require(object as? [String: Any])
  }

  private let echo: MCPServerCore.Caller = { name, args in MCPToolOutcome(text: "ran \(name) \(args["q"] ?? "")") }

  @Test func initializeEchoesASupportedVersionAndAdvertisesTools() async throws {
    let reply = try json(await MCPServerCore.handle(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05"}}"#, call: echo))
    let result = try #require(reply["result"] as? [String: Any])
    #expect(result["protocolVersion"] as? String == "2024-11-05")
    #expect((result["capabilities"] as? [String: Any])?["tools"] != nil)
    #expect((result["serverInfo"] as? [String: Any])?["name"] as? String == "brim")
    let unknown = try json(await MCPServerCore.handle(#"{"jsonrpc":"2.0","id":2,"method":"initialize","params":{"protocolVersion":"1999"}}"#, call: echo))
    #expect((unknown["result"] as? [String: Any])?["protocolVersion"] as? String == "2025-06-18")
  }

  @Test func notificationsGetNoReply() async {
    #expect(await MCPServerCore.handle(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#, call: echo) == nil)
  }

  @Test func listsEveryToolWithASchema() async throws {
    let reply = try json(await MCPServerCore.handle(#"{"jsonrpc":"2.0","id":"a","method":"tools/list"}"#, call: echo))
    #expect(reply["id"] as? String == "a")
    let tools = try #require((reply["result"] as? [String: Any])?["tools"] as? [[String: Any]])
    let names = Set(tools.compactMap { $0["name"] as? String })
    #expect(names == Set(MCPCatalog.tools.map(\.name)))
    #expect(names.isSuperset(of: ["clipboard_search", "tray_list", "tray_add", "now_playing", "media_control", "timers", "calendar_upcoming", "notes", "transform"]))
    #expect(tools.allSatisfy { ($0["inputSchema"] as? [String: Any])?["type"] as? String == "object" })
  }

  @Test func callsRouteToTheCallerAndWrapTheText() async throws {
    let reply = try json(await MCPServerCore.handle(#"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"tray_list","arguments":{"q":"x"}}}"#, call: echo))
    let result = try #require(reply["result"] as? [String: Any])
    let content = try #require(result["content"] as? [[String: Any]])
    #expect(content.first?["text"] as? String == "ran tray_list x")
    #expect(result["isError"] as? Bool == false)
  }

  @Test func unknownToolsAndMethodsAreProtocolErrors() async throws {
    let tool = try json(await MCPServerCore.handle(#"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"rm_rf"}}"#, call: echo))
    #expect((tool["error"] as? [String: Any])?["code"] as? Int == -32602)
    let method = try json(await MCPServerCore.handle(#"{"jsonrpc":"2.0","id":5,"method":"resources/list"}"#, call: echo))
    #expect((method["error"] as? [String: Any])?["code"] as? Int == -32601)
  }

  @Test func malformedInputIsRejectedNotCrashed() async throws {
    let parse = try json(await MCPServerCore.handle("{oops", call: echo))
    #expect((parse["error"] as? [String: Any])?["code"] as? Int == -32700)
    let invalid = try json(await MCPServerCore.handle(#"{"id":9,"method":"ping"}"#, call: echo))
    #expect((invalid["error"] as? [String: Any])?["code"] as? Int == -32600)
    let batch = try json(await MCPServerCore.handle(#"[{"jsonrpc":"2.0","id":1,"method":"ping"}]"#, call: echo))
    #expect((batch["error"] as? [String: Any])?["code"] as? Int == -32600)
  }
}

struct MCPConsentTests {
  @Test func everyToolIsOffUntilTheUserAllowsIt() {
    let settings = AppSettings(defaults: UserDefaults(suiteName: "QS-MCP-\(UUID().uuidString)")!)
    #expect(settings.mcpEnabled == false)
    #expect(settings.mcpAllowedTools.isEmpty)
    for tool in MCPCatalog.tools {
      #expect(MCPGate.decide(tool: tool.name, allowed: settings.mcpAllowedTools, serverEnabled: true) == .denied)
    }
  }

  @Test func allowingNeedsBothTheServerSwitchAndTheToolSwitch() {
    #expect(MCPGate.decide(tool: "tray_list", allowed: ["tray_list"], serverEnabled: true) == .allowed)
    #expect(MCPGate.decide(tool: "tray_list", allowed: ["tray_list"], serverEnabled: false) == .denied)
    #expect(MCPGate.decide(tool: "tray_list", allowed: ["now_playing"], serverEnabled: true) == .denied)
    #expect(MCPGate.decide(tool: "anything_else", allowed: ["anything_else"], serverEnabled: true) == .unknownTool)
  }

  @Test func deniedMessagesTellTheUserWhatToDo() {
    #expect(MCPGate.deniedMessage(tool: "notes", serverEnabled: true).contains("notes"))
    #expect(MCPGate.deniedMessage(tool: "notes", serverEnabled: false).contains("turned off"))
  }

  @Test func allowedToolsPersist() {
    let settings = AppSettings(defaults: UserDefaults(suiteName: "QS-MCP-\(UUID().uuidString)")!)
    settings.mcpAllowedTools = ["notes", "timers"]
    #expect(settings.mcpAllowedTools == ["notes", "timers"])
  }

  @MainActor @Test func theServiceRefusesAndNeverTouchesStateWhenDisabled() async {
    // The shared settings default to off, so a call must be refused without side effects.
    let saved = (AppSettings.shared.mcpEnabled, AppSettings.shared.mcpAllowedTools)
    AppSettings.shared.mcpEnabled = false
    AppSettings.shared.mcpAllowedTools = []
    defer { (AppSettings.shared.mcpEnabled, AppSettings.shared.mcpAllowedTools) = saved }
    let outcome = await MCPAppService.shared.handle(tool: "notes", arguments: ["add_text": "should not be saved"])
    #expect(outcome.isError)
    #expect(!NotesModel.shared.notes.contains { $0.text == "should not be saved" })
  }
}

struct MCPWireAndSetupTests {
  @Test func requestAndResponseLinesRoundTrip() throws {
    let request = try #require(MCPWire.requestLine(tool: "notes", arguments: ["add_text": "hi"]))
    #expect(request.last == 0x0A)
    let parsed = try #require(MCPWire.parseRequest(request.dropLast()))
    #expect(parsed.tool == "notes" && parsed.arguments["add_text"] as? String == "hi")
    let response = MCPWire.responseLine(MCPToolOutcome(text: "ok", isError: true))
    #expect(MCPWire.parseResponse(response.dropLast()) == MCPToolOutcome(text: "ok", isError: true))
    #expect(MCPWire.parseRequest(Data("junk".utf8)) == nil)
  }

  @Test func setupTextIsValidJSONAndQuotesPaths() throws {
    let path = "/Applications/Brim Beta's.app/Contents/MacOS/Brim"
    let object = try #require(JSONSerialization.jsonObject(with: Data(MCPSetupText.configJSON(executable: path).utf8)) as? [String: Any])
    let server = try #require(((object["mcpServers"] as? [String: Any])?["brim"]) as? [String: Any])
    #expect(server["command"] as? String == path && server["args"] as? [String] == ["--mcp"])
    #expect(MCPSetupText.claudeCodeCommand(executable: path) == "claude mcp add brim -- '/Applications/Brim Beta'\\''s.app/Contents/MacOS/Brim' --mcp")
  }

  @Test func argumentHelpersClampAndRejectRelativeOrMissingPaths() throws {
    #expect(MCPAppService.clamp(99, 1...20, default: 5) == 20)
    #expect(MCPAppService.clamp(nil, 1...20, default: 5) == 5)
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("mcp-\(UUID().uuidString).txt")
    try Data("x".utf8).write(to: file)
    defer { try? FileManager.default.removeItem(at: file) }
    let urls = MCPAppService.absolutePaths([file.path, "relative.txt", "/definitely/missing", NSTemporaryDirectory()])
    #expect(urls.map(\.path) == [file.path])
  }
}

/// The real Unix socket and the same forwarding code the `--mcp` bridge uses, with a fake backend.
struct MCPSocketRoundTripTests {
  @Test func bridgeForwardsACallAndGetsTheAnswer() async throws {
    let path = "/tmp/qs-mcp-\(UUID().uuidString.prefix(8)).sock"
    let server = MCPSocketServer(path: path) { tool, args in
      MCPToolOutcome(text: "\(tool):\(args.value["q"] ?? "")", isError: false)
    }
    server.start()
    defer { server.stop() }
    let permissions = try FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? NSNumber
    #expect(permissions?.intValue == 0o600)
    let outcome = await Task.detached { MCPBridge.forward(tool: "notes", arguments: ["q": "hello"], path: path) }.value
    #expect(outcome == MCPToolOutcome(text: "notes:hello", isError: false))
    let missing = await Task.detached { MCPBridge.forward(tool: "notes", arguments: [:], path: "/tmp/qs-nope.sock") }.value
    #expect(missing.isError && missing.text.contains("isn’t running"))
  }
}
