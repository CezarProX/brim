import Darwin
import Foundation

/// Multicast UDP discovery on 224.0.0.167:53317, the LocalSend v2 way. Plain BSD sockets, so
/// there is no dependency and no entitlement beyond the local-network permission.
final class LocalSendDiscovery: @unchecked Sendable {
  enum Failure: Error, LocalizedError {
    case socket(String)
    var errorDescription: String? {
      if case .socket(let step) = self { return "Couldn’t listen for LocalSend devices (\(step))." }
      return nil
    }
  }

  private let queue = DispatchQueue(label: "brim.localsend.discovery")
  private var descriptor: Int32 = -1
  private var source: DispatchSourceRead?
  private var identity: LocalSendDevice
  private var onPeer: (@Sendable (LocalSendDevice, String) -> Void)?
  private var lastReply: [String: Date] = [:]

  init(identity: LocalSendDevice) { self.identity = identity }

  func start(onPeer: @escaping @Sendable (LocalSendDevice, String) -> Void) throws {
    try queue.sync {
      guard descriptor < 0 else { return }
      let fd = socket(AF_INET, SOCK_DGRAM, 0)
      guard fd >= 0 else { throw Failure.socket("socket") }
      var on: Int32 = 1
      setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &on, socklen_t(MemoryLayout<Int32>.size))
      setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, &on, socklen_t(MemoryLayout<Int32>.size))
      var address = sockaddr_in()
      address.sin_family = sa_family_t(AF_INET)
      address.sin_port = LocalSendProtocol.port.bigEndian
      address.sin_addr.s_addr = INADDR_ANY.bigEndian
      let bound = withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
      }
      guard bound == 0 else { close(fd); throw Failure.socket("bind") }
      var membership = ip_mreq(imr_multiaddr: in_addr(s_addr: inet_addr(LocalSendProtocol.multicastAddress)), imr_interface: in_addr(s_addr: INADDR_ANY.bigEndian))
      guard setsockopt(fd, IPPROTO_IP, IP_ADD_MEMBERSHIP, &membership, socklen_t(MemoryLayout<ip_mreq>.size)) == 0 else {
        close(fd)
        throw Failure.socket("join")
      }
      descriptor = fd
      self.onPeer = onPeer
      let reader = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
      reader.setEventHandler { [weak self] in self?.readPending() }
      reader.setCancelHandler { close(fd) }
      source = reader
      reader.resume()
    }
  }

  func stop() {
    queue.sync {
      source?.cancel()
      source = nil
      descriptor = -1
      onPeer = nil
    }
  }

  func updateIdentity(_ device: LocalSendDevice) { queue.async { self.identity = device } }

  /// Tells the network we are here; peers answer with their own announcement.
  func announce() { queue.async { self.send(announce: true) } }

  private func send(announce: Bool) {
    guard descriptor >= 0, let data = LocalSendCodec.announcement(for: identity, announce: announce) else { return }
    var target = sockaddr_in()
    target.sin_family = sa_family_t(AF_INET)
    target.sin_port = LocalSendProtocol.port.bigEndian
    target.sin_addr.s_addr = inet_addr(LocalSendProtocol.multicastAddress)
    data.withUnsafeBytes { bytes in
      withUnsafePointer(to: &target) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
          _ = sendto(descriptor, bytes.baseAddress, data.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
      }
    }
  }

  private func readPending() {
    var buffer = [UInt8](repeating: 0, count: 4096)
    var sender = sockaddr_in()
    var length = socklen_t(MemoryLayout<sockaddr_in>.size)
    let count = withUnsafeMutablePointer(to: &sender) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { recvfrom(descriptor, &buffer, buffer.count, 0, $0, &length) }
    }
    guard count > 0, let device = LocalSendCodec.decodeAnnouncement(Data(buffer.prefix(count))),
      device.fingerprint != identity.fingerprint
    else { return }
    var raw = sender.sin_addr
    var text = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
    inet_ntop(AF_INET, &raw, &text, socklen_t(INET_ADDRSTRLEN))
    let address = String(cString: text)
    onPeer?(device, address)
    if device.announce == true, shouldReply(to: device.fingerprint) { send(announce: false) }
  }

  /// At most one reply per peer every few seconds, so two chatty devices cannot loop.
  private func shouldReply(to fingerprint: String) -> Bool {
    let now = Date()
    if let last = lastReply[fingerprint], now.timeIntervalSince(last) < 3 { return false }
    lastReply[fingerprint] = now
    return true
  }
}
