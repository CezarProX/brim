import Darwin
import Foundation

/// The Unix socket the running app listens on and the `--mcp` bridge connects to.
/// It lives in Application Support (mode 0600) and only the same user may connect.
enum MCPSocket {
  static var path: String {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Brim/mcp.sock").path
  }

  static func address(for path: String) -> sockaddr_un? {
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let bytes = Array(path.utf8CString)
    guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { return nil }
    withUnsafeMutableBytes(of: &address.sun_path) { raw in
      for (index, byte) in bytes.enumerated() { raw[index] = UInt8(bitPattern: byte) }
    }
    return address
  }

  /// Reads bytes until a newline (or the cap). Returns nil at end of stream with nothing read.
  static func readLine(_ fd: Int32) -> Data? {
    var line = Data()
    var byte: UInt8 = 0
    while line.count < MCPWire.maxLine {
      let count = read(fd, &byte, 1)
      if count <= 0 { return line.isEmpty ? nil : line }
      if byte == 0x0A { return line }
      line.append(byte)
    }
    return nil
  }

  static func writeAll(_ fd: Int32, _ data: Data) {
    data.withUnsafeBytes { raw in
      var offset = 0
      while offset < raw.count {
        let written = write(fd, raw.baseAddress!.advanced(by: offset), raw.count - offset)
        if written <= 0 { return }
        offset += written
      }
    }
  }
}

/// Accepts bridge connections and answers each tool call through `MCPAppService`.
final class MCPSocketServer: @unchecked Sendable {
  typealias Handler = @Sendable (String, UncheckedBox<[String: Any]>) async -> MCPToolOutcome
  static let shared = MCPSocketServer(path: MCPSocket.path) { tool, arguments in
    await MainActor.run { MCPAppService.shared }.handle(tool: tool, arguments: arguments.value)
  }

  private let path: String
  private let handler: Handler
  private var listener: Int32 = -1
  private let queue = DispatchQueue(label: "brim.mcp.socket", attributes: .concurrent)
  private let lock = NSLock()

  init(path: String, handler: @escaping Handler) {
    self.path = path
    self.handler = handler
  }

  func start() {
    lock.lock()
    defer { lock.unlock() }
    guard listener < 0 else { return }
    let folder = (path as NSString).deletingLastPathComponent
    try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    unlink(path)
    guard var address = MCPSocket.address(for: path) else { return }
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { return }
    let bound = withUnsafePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
    }
    guard bound == 0, listen(fd, 8) == 0 else { close(fd); return }
    chmod(path, 0o600)
    listener = fd
    queue.async { [weak self] in self?.acceptLoop(fd) }
  }

  func stop() {
    lock.lock()
    defer { lock.unlock() }
    guard listener >= 0 else { return }
    shutdown(listener, SHUT_RDWR)
    close(listener)
    listener = -1
    unlink(path)
  }

  private func acceptLoop(_ fd: Int32) {
    while true {
      let client = accept(fd, nil, nil)
      if client < 0 { return }
      queue.async { [handler] in Self.serve(client, handler: handler) }
    }
  }

  private static func serve(_ client: Int32, handler: @escaping Handler) {
    defer { close(client) }
    var uid: uid_t = 0
    var gid: gid_t = 0
    guard getpeereid(client, &uid, &gid) == 0, uid == getuid() else { return }
    guard let line = MCPSocket.readLine(client), let request = MCPWire.parseRequest(line) else {
      MCPSocket.writeAll(client, MCPWire.responseLine(MCPToolOutcome(text: "Malformed request.", isError: true)))
      return
    }
    let semaphore = DispatchSemaphore(value: 0)
    var outcome = MCPToolOutcome(text: "Brim did not answer.", isError: true)
    let tool = request.tool
    let arguments = UncheckedBox(request.arguments)
    Task {
      outcome = await handler(tool, arguments)
      semaphore.signal()
    }
    if semaphore.wait(timeout: .now() + 30) == .timedOut {
      outcome = MCPToolOutcome(text: "Brim took too long to answer.", isError: true)
    }
    MCPSocket.writeAll(client, MCPWire.responseLine(outcome))
  }
}

/// Carries a non-Sendable JSON dictionary across a task boundary; it is only read afterwards.
struct UncheckedBox<T>: @unchecked Sendable {
  let value: T
  init(_ value: T) { self.value = value }
}
