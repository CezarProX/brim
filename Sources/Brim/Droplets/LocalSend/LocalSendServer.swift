import Foundation
import Network
import Security

/// An HTTP status used as an error value by the handlers.
struct LocalSendStatus: Error, Equatable, Sendable {
  let code: Int
  static let forbidden = LocalSendStatus(code: 403)
  static let conflict = LocalSendStatus(code: 409)
  static let tooMany = LocalSendStatus(code: 429)
  static let notFound = LocalSendStatus(code: 404)
}

/// What the model decides for incoming requests. All closures are async because they may ask the user.
struct LocalSendServerHandlers: Sendable {
  var info: @Sendable () async -> LocalSendDevice
  var peerSeen: @Sendable (LocalSendDevice, String) async -> Void
  /// Returns a response when the user accepted, or the HTTP status to answer with.
  var prepare: @Sendable (LocalSendPrepareRequest) async -> Result<LocalSendPrepareResponse, LocalSendStatus>
  /// Where an upload goes and its declared size, or the HTTP status to refuse with.
  var destination: @Sendable (String, String, String) async -> Result<(URL, Int64), LocalSendStatus>
  var fileFinished: @Sendable (String, String, Bool) async -> Void
  var cancel: @Sendable (String) async -> Void
}

/// A small HTTPS server for the LocalSend receive API on top of Network.framework.
final class LocalSendServer: @unchecked Sendable {
  private let queue = DispatchQueue(label: "brim.localsend.server")
  private var listener: NWListener?
  private let handlers: LocalSendServerHandlers
  private static let maxJSONBody = 1_000_000

  init(handlers: LocalSendServerHandlers) { self.handlers = handlers }

  /// Starts listening with the given identity. Tries the standard port, then any free port;
  /// returns the port that was bound.
  func start(identity: SecIdentity) async throws -> UInt16 {
    stop()
    let options = NWProtocolTLS.Options()
    if let secIdentity = sec_identity_create(identity) {
      sec_protocol_options_set_local_identity(options.securityProtocolOptions, secIdentity)
    }
    for candidate in [LocalSendProtocol.port, 0] {
      let parameters = NWParameters(tls: options, tcp: NWProtocolTCP.Options())
      parameters.allowLocalEndpointReuse = true
      let port = NWEndpoint.Port(rawValue: candidate) ?? .any
      guard let listener = try? NWListener(using: parameters, on: port) else { continue }
      if let bound = await bind(listener) {
        self.listener = listener
        return bound
      }
    }
    throw LocalSendIdentity.Failure.load
  }

  func stop() {
    listener?.cancel()
    listener = nil
  }

  private func bind(_ listener: NWListener) async -> UInt16? {
    await withCheckedContinuation { continuation in
      let finished = Locked(false)
      listener.stateUpdateHandler = { state in
        switch state {
        case .ready:
          if finished.setTrue() { continuation.resume(returning: listener.port?.rawValue) }
        case .failed, .cancelled:
          if finished.setTrue() { continuation.resume(returning: nil) }
        default: break
        }
      }
      listener.newConnectionHandler = { [handlers, queue] connection in
        connection.start(queue: queue)
        Task { await LocalSendConnectionHandler(connection: connection, handlers: handlers).run() }
      }
      listener.start(queue: queue)
    }
  }
}

/// A tiny lock-protected flag so a continuation is resumed exactly once.
final class Locked: @unchecked Sendable {
  private var value: Bool
  private let lock = NSLock()
  init(_ value: Bool) { self.value = value }
  /// Sets the flag; true only the first time.
  func setTrue() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    if value { return false }
    value = true
    return true
  }
}

/// Serves one connection: read the request head, route it, answer, close.
struct LocalSendConnectionHandler {
  let connection: NWConnection
  let handlers: LocalSendServerHandlers

  func run() async {
    defer { connection.cancel() }
    var buffer = Data()
    var head: LocalSendRequestHead?
    var consumed = 0
    while head == nil {
      switch LocalSendHTTP.parseHead(buffer) {
      case .head(let parsed, let used):
        head = parsed
        consumed = used
      case .invalid: return await send(400)
      case .needMore:
        guard let chunk = await receive() else { return }
        buffer.append(chunk)
      }
    }
    guard let head else { return }
    let leftover = buffer.dropFirst(consumed)
    await route(head, leftover: Data(leftover))
  }

  private func route(_ head: LocalSendRequestHead, leftover: Data) async {
    switch (head.method, head.path) {
    case ("GET", LocalSendProtocol.Path.info):
      await send(200, json: LocalSendCodec.encode(await handlers.info()))
    case ("POST", LocalSendProtocol.Path.register):
      guard let body = await readBody(head, leftover: leftover) else { return await send(400) }
      if let peer = LocalSendCodec.decodeAnnouncement(body) { await handlers.peerSeen(peer, remoteAddress()) }
      await send(200, json: LocalSendCodec.encode(await handlers.info()))
    case ("POST", LocalSendProtocol.Path.prepareUpload):
      await prepare(head, leftover: leftover)
    case ("POST", LocalSendProtocol.Path.upload):
      await upload(head, leftover: leftover)
    case ("POST", LocalSendProtocol.Path.cancel):
      if let id = head.query["sessionId"] { await handlers.cancel(id) }
      await send(200)
    default:
      await send(404)
    }
  }

  private func prepare(_ head: LocalSendRequestHead, leftover: Data) async {
    guard let body = await readBody(head, leftover: leftover),
      let request = try? JSONDecoder().decode(LocalSendPrepareRequest.self, from: body)
    else { return await send(400) }
    switch await handlers.prepare(request) {
    case .success(let response):
      if response.files.isEmpty { await send(204) } else { await send(200, json: LocalSendCodec.encode(response)) }
    case .failure(let status): await send(status.code)
    }
  }

  private func upload(_ head: LocalSendRequestHead, leftover: Data) async {
    let query = head.query
    guard let session = query["sessionId"], let file = query["fileId"], let token = query["token"] else {
      return await send(400)
    }
    switch await handlers.destination(session, file, token) {
    case .failure(let status): await send(status.code)
    case .success(let (url, declared)):
      guard head.contentLength >= 0, Int64(head.contentLength) <= declared else { return await send(413) }
      let stored = await stream(to: url, length: head.contentLength, leftover: leftover)
      await handlers.fileFinished(session, file, stored)
      await send(stored ? 200 : 500)
    }
  }

  /// Writes exactly `length` body bytes to `url`; removes the partial file on failure.
  private func stream(to url: URL, length: Int, leftover: Data) async -> Bool {
    guard FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o644]),
      let handle = try? FileHandle(forWritingTo: url)
    else { return false }
    var written = 0
    var ok = true
    do {
      defer { try? handle.close() }
      var pending = leftover.prefix(length)
      while true {
        if !pending.isEmpty {
          try handle.write(contentsOf: pending)
          written += pending.count
        }
        if written >= length { break }
        guard let chunk = await receive() else { ok = false; break }
        pending = chunk.prefix(length - written)
      }
    } catch { ok = false }
    ok = ok && written == length
    if !ok { try? FileManager.default.removeItem(at: url) }
    return ok
  }

  private func readBody(_ head: LocalSendRequestHead, leftover: Data) async -> Data? {
    let length = head.contentLength
    guard length >= 0, length <= 1_000_000 else { return nil }
    var body = leftover
    while body.count < length {
      guard let chunk = await receive() else { return nil }
      body.append(chunk)
    }
    return body.prefix(length)
  }

  private func remoteAddress() -> String {
    if case .hostPort(let host, _) = connection.endpoint { return "\(host)".components(separatedBy: "%").first ?? "" }
    return ""
  }

  private func receive() async -> Data? {
    await withCheckedContinuation { continuation in
      connection.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) { data, _, isComplete, error in
        continuation.resume(returning: error == nil && !(data?.isEmpty ?? true) ? data : (isComplete ? nil : nil))
      }
    }
  }

  private func send(_ status: Int, json: Data? = nil) async {
    let payload = LocalSendHTTP.response(status: status, json: json)
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      connection.send(content: payload, completion: .contentProcessed { _ in continuation.resume() })
    }
  }
}
