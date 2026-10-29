import Darwin
import Foundation

/// `Brim --mcp`: an MCP server on stdin/stdout for AI apps to launch. It answers the
/// protocol itself and forwards each tool call to the running app over the Unix socket, where
/// the consent gate decides. If the app is not running, calls report that.
enum MCPBridge {
  static func runAndExit() -> Never {
    let lines = AnyIterator { readLine(strippingNewline: true) }
    for line in lines where !line.trimmingCharacters(in: .whitespaces).isEmpty {
      let semaphore = DispatchSemaphore(value: 0)
      var reply: String?
      Task.detached {
        reply = await MCPServerCore.handle(line, call: { forward(tool: $0, arguments: $1) })
        semaphore.signal()
      }
      semaphore.wait()
      if let reply { print(reply); fflush(stdout) }
    }
    exit(0)
  }

  static func forward(tool: String, arguments: [String: Any], path: String = MCPSocket.path) -> MCPToolOutcome {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0, var address = MCPSocket.address(for: path) else {
      return MCPToolOutcome(text: unavailable, isError: true)
    }
    defer { close(fd) }
    let connected = withUnsafePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
    }
    guard connected == 0, let request = MCPWire.requestLine(tool: tool, arguments: arguments) else {
      return MCPToolOutcome(text: unavailable, isError: true)
    }
    MCPSocket.writeAll(fd, request)
    guard let line = MCPSocket.readLine(fd), let outcome = MCPWire.parseResponse(line) else {
      return MCPToolOutcome(text: "Brim did not answer.", isError: true)
    }
    return outcome
  }

  static let unavailable = "Brim isn’t running, or its MCP server is off. Open Brim and enable Settings > Home & Widgets > MCP Server."
}
