import Foundation

struct MCPToolOutcome: Equatable {
  var text: String
  var isError: Bool = false
}

/// JSON-RPC 2.0 handling for the MCP stdio server. Pure: tool execution is injected, so this is
/// what the `--mcp` bridge runs and what the tests drive.
enum MCPServerCore {
  typealias Caller = (String, [String: Any]) async -> MCPToolOutcome
  static let supportedVersions = ["2025-06-18", "2025-03-26", "2024-11-05"]
  static let serverName = "brim"

  /// Handles one JSON-RPC line. Returns the response line, or nil for notifications.
  static func handle(_ line: String, call: Caller) async -> String? {
    guard let data = line.data(using: .utf8), let any = try? JSONSerialization.jsonObject(with: data) else {
      return error(id: NSNull(), code: -32700, message: "Parse error")
    }
    guard let request = any as? [String: Any], request["jsonrpc"] as? String == "2.0",
      let method = request["method"] as? String
    else { return error(id: (any as? [String: Any])?["id"] ?? NSNull(), code: -32600, message: "Invalid request") }
    guard let id = request["id"] else { return nil }  // a notification
    let params = request["params"] as? [String: Any] ?? [:]
    switch method {
    case "initialize": return result(id: id, initializeResult(params))
    case "ping": return result(id: id, [:])
    case "tools/list": return result(id: id, ["tools": MCPCatalog.tools.map(toolJSON)])
    case "tools/call": return await callTool(id: id, params: params, call: call)
    default: return error(id: id, code: -32601, message: "Method not found: \(method)")
    }
  }

  private static func initializeResult(_ params: [String: Any]) -> [String: Any] {
    let asked = params["protocolVersion"] as? String ?? ""
    return [
      "protocolVersion": supportedVersions.contains(asked) ? asked : supportedVersions[0],
      "capabilities": ["tools": ["listChanged": false]],
      "serverInfo": ["name": serverName, "version": "1.0"],
      "instructions": "Tools expose this Mac's Brim island. Each tool works only if the user allowed it in Brim settings.",
    ]
  }

  private static func toolJSON(_ spec: MCPToolSpec) -> [String: Any] {
    ["name": spec.name, "description": spec.description, "inputSchema": spec.inputSchema]
  }

  private static func callTool(id: Any, params: [String: Any], call: Caller) async -> String? {
    guard let name = params["name"] as? String, MCPCatalog.spec(named: name) != nil else {
      return error(id: id, code: -32602, message: "Unknown tool")
    }
    let outcome = await call(name, params["arguments"] as? [String: Any] ?? [:])
    return result(
      id: id, ["content": [["type": "text", "text": outcome.text]], "isError": outcome.isError])
  }

  // MARK: Encoding

  static func result(id: Any, _ value: [String: Any]) -> String? {
    encode(["jsonrpc": "2.0", "id": id, "result": value])
  }

  static func error(id: Any, code: Int, message: String) -> String? {
    encode(["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]])
  }

  private static func encode(_ object: [String: Any]) -> String? {
    guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return nil }
    return String(data: data, encoding: .utf8)
  }
}

/// The one-line wire format between the `--mcp` bridge and the running app, over the Unix socket.
enum MCPWire {
  static let maxLine = 1_000_000

  static func requestLine(tool: String, arguments: [String: Any]) -> Data? {
    guard var data = try? JSONSerialization.data(withJSONObject: ["tool": tool, "arguments": arguments], options: [.sortedKeys])
    else { return nil }
    data.append(0x0A)
    return data
  }

  static func parseRequest(_ line: Data) -> (tool: String, arguments: [String: Any])? {
    guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any], let tool = object["tool"] as? String
    else { return nil }
    return (tool, object["arguments"] as? [String: Any] ?? [:])
  }

  static func responseLine(_ outcome: MCPToolOutcome) -> Data {
    var data = (try? JSONSerialization.data(withJSONObject: ["text": outcome.text, "isError": outcome.isError], options: [.sortedKeys])) ?? Data()
    data.append(0x0A)
    return data
  }

  static func parseResponse(_ line: Data) -> MCPToolOutcome? {
    guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any], let text = object["text"] as? String
    else { return nil }
    return MCPToolOutcome(text: text, isError: object["isError"] as? Bool ?? false)
  }
}
