import Darwin
import Foundation

/// Unix-domain-socket plumbing shared by the app (server) and the hook (client). Requests and
/// responses are one JSON object per line.
enum AgentQuestionSocket {
  static var path: String {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Brim/agent.sock").path
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

  /// Reads up to a newline. Nil on end of stream with nothing read, on a timeout, or past `limit` bytes.
  static func readLine(_ fd: Int32, limit: Int = AgentQuestionRequest.Limits.maxBytes) -> Data? {
    var line = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while line.count <= limit {
      let count = read(fd, &buffer, buffer.count)
      if count <= 0 { return line.isEmpty ? nil : line }
      if let newline = buffer[0..<count].firstIndex(of: 0x0A) {
        line.append(contentsOf: buffer[0..<newline])
        return line.count <= limit ? line : nil
      }
      line.append(contentsOf: buffer[0..<count])
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

  static func setReceiveTimeout(_ fd: Int32, seconds: Int) {
    var timeout = timeval(tv_sec: seconds, tv_usec: 0)
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
  }

  /// True once the peer has closed its end (the hook was killed or gave up).
  static func peerClosed(_ fd: Int32) -> Bool {
    var probe = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
    guard poll(&probe, 1, 0) > 0 else { return false }
    if probe.revents & Int16(POLLHUP | POLLERR) != 0 { return true }
    var byte: UInt8 = 0
    return recv(fd, &byte, 1, MSG_PEEK | MSG_DONTWAIT) == 0
  }

  /// Client side: sends one request line and waits for the reply. Nil when the app is not listening.
  static func request(_ payload: Data, path: String = AgentQuestionSocket.path, waitSeconds: Int) -> AgentQuestionResponse? {
    guard FileManager.default.fileExists(atPath: path), var address = address(for: path) else { return nil }
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { return nil }
    defer { close(fd) }
    let connected = withUnsafePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
    }
    guard connected == 0 else { return nil }
    setReceiveTimeout(fd, seconds: waitSeconds)
    writeAll(fd, payload + Data([0x0A]))
    guard let line = readLine(fd) else { return nil }
    return AgentQuestionResponse.parse(line)
  }
}

/// Accepts hook connections for the island's question cards. Local only: a 0600 socket inside a 0700
/// folder, and every peer must be the same user.
final class AgentQuestionServer: @unchecked Sendable {
  typealias Asker = @Sendable (AgentQuestionRequest) async -> AgentQuestionResponse

  private let path: String
  private let asker: Asker
  private var listener: Int32 = -1
  private let lock = NSLock()
  private let queue = DispatchQueue(label: "brim.agent.questions", attributes: .concurrent)
  /// Connections being served at once; extra ones are refused so a flood cannot pile up threads.
  private let slots = DispatchSemaphore(value: 16)

  init(path: String = AgentQuestionSocket.path, asker: @escaping Asker) {
    self.path = path
    self.asker = asker
  }

  var isRunning: Bool { lock.withLock { listener >= 0 } }

  func start() {
    lock.lock()
    defer { lock.unlock() }
    guard listener < 0 else { return }
    let folder = (path as NSString).deletingLastPathComponent
    try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    unlink(path)
    guard var address = AgentQuestionSocket.address(for: path) else { return }
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
      guard slots.wait(timeout: .now()) == .success else {
        AgentQuestionSocket.writeAll(client, AgentQuestionResponse(.busy).wireData())
        close(client)
        continue
      }
      queue.async { [asker, slots] in
        defer { slots.signal() }
        Self.serve(client, asker: asker)
      }
    }
  }

  private static func serve(_ client: Int32, asker: @escaping Asker) {
    defer { close(client) }
    var uid: uid_t = 0
    var gid: gid_t = 0
    guard getpeereid(client, &uid, &gid) == 0, uid == getuid() else { return }
    AgentQuestionSocket.setReceiveTimeout(client, seconds: 5)
    guard let line = AgentQuestionSocket.readLine(client), let request = try? AgentQuestionRequest.parse(line) else {
      AgentQuestionSocket.writeAll(client, AgentQuestionResponse(.invalid).wireData())
      return
    }
    let box = ResultBox()
    let task = Task {
      let response = await asker(request)
      box.set(response)
    }
    while !box.isSet {
      if AgentQuestionSocket.peerClosed(client) { task.cancel(); return }
      usleep(100_000)
    }
    AgentQuestionSocket.writeAll(client, box.value.wireData())
  }
}

private final class ResultBox: @unchecked Sendable {
  private let lock = NSLock()
  private var response: AgentQuestionResponse?
  var isSet: Bool { lock.withLock { response != nil } }
  var value: AgentQuestionResponse { lock.withLock { response ?? AgentQuestionResponse(.dismissed) } }
  func set(_ value: AgentQuestionResponse) { lock.withLock { response = value } }
}

/// Starts and stops the server with the Settings switch.
@MainActor
final class AgentQuestionBridge {
  static let shared = AgentQuestionBridge()
  private let server = AgentQuestionServer { request in await AgentQuestionCoordinator.shared.ask(request) }

  func startIfEnabled() {
    guard AppSettings.shared.agentQuestionsEnabled else { return }
    server.start()
    AgentQuestionPanelController.shared.start()
  }

  func setEnabled(_ on: Bool) {
    AppSettings.shared.agentQuestionsEnabled = on
    if on {
      startIfEnabled()
    } else {
      AgentQuestionCoordinator.shared.dismissAll()
      server.stop()
    }
  }

  func shutdown() {
    AgentQuestionCoordinator.shared.dismissAll()
    server.stop()
  }
}
