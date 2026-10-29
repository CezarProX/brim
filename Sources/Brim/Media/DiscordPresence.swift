import Darwin
import Foundation

/// Rich Presence over Discord's local socket (`$TMPDIR/discord-ipc-N`). Nothing leaves the Mac except
/// through your own Discord client. Off by default; needs the client id of a Discord application you
/// created (https://discord.com/developers/applications).
@MainActor
final class DiscordPresence {
  static let shared = DiscordPresence()
  private let queue = DispatchQueue(label: "brim.discord-ipc", qos: .utility)
  private let connection = DiscordConnection()
  private var lastKey: String?
  private var lastSent = Date.distantPast

  func sync(track: NowPlayingTrack?, settings: AppSettings) {
    let clientID = settings.discordClientID
    guard settings.discordPresenceEnabled, DiscordIPCProtocol.isValidClientID(clientID) else {
      if lastKey != nil { lastKey = nil; send(.disconnect, clientID: clientID) }
      return
    }
    guard let track else { if lastKey != nil { lastKey = nil; send(.clear, clientID: clientID) }; return }
    let snapshot = track.snapshot
    let key = "\(snapshot.title)|\(snapshot.artist)|\(snapshot.isPlaying)"
    guard key != lastKey, Date().timeIntervalSince(lastSent) > 2 else { return }
    lastKey = key
    lastSent = Date()
    send(.update(snapshot: snapshot, elapsed: track.position(at: Date())), clientID: clientID)
  }

  private func send(_ command: DiscordConnection.Command, clientID: String) {
    let connection = connection
    queue.async { connection.perform(command, clientID: clientID) }
  }
}

/// Blocking socket work, confined to the presence queue.
final class DiscordConnection: @unchecked Sendable {
  enum Command {
    case update(snapshot: NowPlayingSnapshot, elapsed: TimeInterval)
    case clear, disconnect
  }
  private var fd: Int32 = -1
  private var clientID = ""

  func perform(_ command: Command, clientID: String) {
    switch command {
    case .disconnect: close()
    case .clear: if fd >= 0 { write { try DiscordIPCProtocol.clearActivity(pid: getpid(), nonce: UUID().uuidString) } }
    case let .update(snapshot, elapsed):
      if fd < 0 || self.clientID != clientID { close(); connect(clientID: clientID) }
      guard fd >= 0 else { return }
      write {
        try DiscordIPCProtocol.setActivity(
          title: snapshot.title, artist: snapshot.artist, album: snapshot.album, elapsed: elapsed,
          duration: snapshot.duration, isPlaying: snapshot.isPlaying, pid: getpid(), nonce: UUID().uuidString)
      }
    }
  }

  private func connect(clientID: String) {
    let base = ProcessInfo.processInfo.environment["TMPDIR"] ?? NSTemporaryDirectory()
    for index in 0..<10 {
      let path = (base as NSString).appendingPathComponent("discord-ipc-\(index)")
      let socketFD = openSocket(path)
      guard socketFD >= 0 else { continue }
      fd = socketFD
      self.clientID = clientID
      guard let hello = try? DiscordIPCProtocol.handshake(clientID: clientID), writeAll(hello), awaitReady() else {
        close(); continue
      }
      return
    }
  }

  private func openSocket(_ path: String) -> Int32 {
    let socketFD = socket(AF_UNIX, SOCK_STREAM, 0)
    guard socketFD >= 0 else { return -1 }
    var noSigPipe: Int32 = 1
    setsockopt(socketFD, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
    var timeout = timeval(tv_sec: 2, tv_usec: 0)
    setsockopt(socketFD, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    setsockopt(socketFD, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let bytes = Array(path.utf8)
    guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else { Darwin.close(socketFD); return -1 }
    withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
    let result = withUnsafePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        Darwin.connect(socketFD, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
      }
    }
    if result != 0 { Darwin.close(socketFD); return -1 }
    return socketFD
  }

  /// Waits for the READY dispatch so a wrong client id is noticed instead of silently ignored.
  private func awaitReady() -> Bool {
    var buffer = Data()
    var chunk = [UInt8](repeating: 0, count: 2048)
    while buffer.count < DiscordIPCProtocol.maxPayload {
      let count = read(fd, &chunk, chunk.count)
      guard count > 0 else { return false }
      buffer.append(contentsOf: chunk[0..<count])
      guard let frame = try? DiscordIPCProtocol.parse(buffer) else { continue }
      return frame.opcode == .frame && String(decoding: frame.payload, as: UTF8.self).contains("READY")
    }
    return false
  }

  private func write(_ build: () throws -> Data) {
    guard let data = try? build(), writeAll(data) else { close(); return }
    // Drain Discord's acknowledgement so its buffer never fills; the content is not needed.
    var scratch = [UInt8](repeating: 0, count: 4096)
    _ = recv(fd, &scratch, scratch.count, MSG_DONTWAIT)
  }

  private func writeAll(_ data: Data) -> Bool {
    var sent = 0
    return data.withUnsafeBytes { raw in
      while sent < data.count {
        let n = send(fd, raw.baseAddress!.advanced(by: sent), data.count - sent, 0)
        if n <= 0 { return false }
        sent += n
      }
      return true
    }
  }

  private func close() {
    if fd >= 0 { Darwin.close(fd) }
    fd = -1
  }
}
