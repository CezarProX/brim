import AppKit
import SwiftUI

struct LocalSendPeer: Identifiable, Equatable {
  let device: LocalSendDevice
  let host: String
  let seenAt: Date
  var id: String { device.fingerprint }
}

struct LocalSendTransfer: Identifiable, Equatable {
  enum Phase: Equatable { case waiting, sending, done, failed(String) }
  let id = UUID()
  let alias: String
  var phase: Phase = .waiting
  var progress: Double = 0
}

/// Finds nearby LocalSend devices, sends files to them, and (if turned on) receives files.
@MainActor
final class LocalSendModel: ObservableObject {
  static let shared = LocalSendModel()
  @Published private(set) var peers: [LocalSendPeer] = []
  @Published private(set) var transfers: [LocalSendTransfer] = []
  @Published private(set) var isRunning = false
  @Published private(set) var errorMessage: String?
  private var discovery: LocalSendDiscovery?
  private var server: LocalSendServer?
  private var identity: LocalSendDevice?
  private var session: LocalSendReceiveSession?
  private let settings = AppSettings.shared

  /// Starts discovery and the receive server when LocalSend is enabled in settings.
  func start() async {
    guard settings.localSendEnabled, !isRunning else { return }
    errorMessage = nil
    do {
      let material = try await LocalSendIdentity.load()
      let handlers = makeHandlers()
      let server = LocalSendServer(handlers: handlers)
      let port = try await server.start(identity: material.identity)
      let device = Self.makeDevice(alias: settings.localSendAlias, fingerprint: material.fingerprint, port: Int(port))
      let discovery = LocalSendDiscovery(identity: device)
      try discovery.start { [weak self] peer, host in
        Task { @MainActor in self?.sawPeer(peer, host: host) }
      }
      self.server = server
      self.identity = device
      self.discovery = discovery
      isRunning = true
      discovery.announce()
    } catch {
      errorMessage = error.localizedDescription
      stop()
    }
  }

  func stop() {
    discovery?.stop()
    server?.stop()
    discovery = nil
    server = nil
    identity = nil
    session = nil
    peers = []
    isRunning = false
  }

  /// Fills the model with fixed content for previews and render tests.
  func loadPreview(peers: [LocalSendPeer], transfers: [LocalSendTransfer], running: Bool = true) {
    self.peers = peers
    self.transfers = transfers
    isRunning = running
  }

  /// Re-announces so devices answer again; older entries that stay silent drop off.
  func refresh() {
    let cutoff = Date()
    discovery?.announce()
    Task { @MainActor in
      try? await Task.sleep(for: .seconds(3))
      peers.removeAll { $0.seenAt < cutoff }
    }
  }

  nonisolated static func makeDevice(alias: String, fingerprint: String, port: Int) -> LocalSendDevice {
    LocalSendDevice(
      alias: alias, version: LocalSendProtocol.version, deviceModel: "Mac", deviceType: "desktop",
      fingerprint: fingerprint, port: port, protocol: "https", download: false, announce: nil)
  }

  private func sawPeer(_ device: LocalSendDevice, host: String) {
    let peer = LocalSendPeer(device: device, host: host, seenAt: .now)
    peers = (peers.filter { $0.id != peer.id } + [peer]).sorted { $0.device.alias.localizedCaseInsensitiveCompare($1.device.alias) == .orderedAscending }
  }

  // MARK: Sending

  func send(_ files: [URL], to peer: LocalSendPeer) {
    guard let identity else { return }
    let transfer = LocalSendTransfer(alias: peer.device.alias)
    transfers.append(transfer)
    let id = transfer.id
    let client = LocalSendClient(device: peer.device, host: peer.host, sender: identity)
    Task {
      do {
        update(id) { $0.phase = .sending }
        try await client.send(files: files) { [weak self] value in
          Task { @MainActor in self?.update(id) { $0.progress = value } }
        }
        update(id) { $0.phase = .done; $0.progress = 1 }
        IslandFlashCenter.shared.show("Sent to \(peer.device.alias)", symbol: "paperplane.fill", tint: .green)
      } catch {
        update(id) { $0.phase = .failed(error.localizedDescription) }
      }
    }
  }

  func clearFinished() {
    transfers.removeAll {
      switch $0.phase {
      case .done, .failed: true
      case .waiting, .sending: false
      }
    }
  }

  private func update(_ id: UUID, _ change: (inout LocalSendTransfer) -> Void) {
    guard let index = transfers.firstIndex(where: { $0.id == id }) else { return }
    change(&transfers[index])
  }

  // MARK: Receiving

  private func makeHandlers() -> LocalSendServerHandlers {
    LocalSendServerHandlers(
      info: { [weak self] in await self?.identity ?? Self.makeDevice(alias: "Brim", fingerprint: "", port: 0) },
      peerSeen: { [weak self] device, host in await self?.sawPeer(device, host: host) },
      prepare: { [weak self] request in await self?.prepare(request) ?? .failure(.forbidden) },
      destination: { [weak self] session, file, token in await self?.destination(session, file, token) ?? .failure(.notFound) },
      fileFinished: { [weak self] session, file, ok in await self?.finished(session, file, ok) },
      cancel: { [weak self] id in await self?.cancelSession(id) })
  }

  private func prepare(_ request: LocalSendPrepareRequest) async -> Result<LocalSendPrepareResponse, LocalSendStatus> {
    guard settings.localSendReceiveEnabled else { return .failure(.forbidden) }
    guard session == nil else { return .failure(.conflict) }
    guard let folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
      return .failure(.forbidden)
    }
    let metas = Array(request.files.values)
    guard await confirm(sender: request.info, files: metas) else { return .failure(.forbidden) }
    let next = LocalSendReceiveSession(sender: request.info, files: metas, folder: folder)
    session = next
    return .success(LocalSendPrepareResponse(sessionId: next.id, files: next.tokens))
  }

  private func destination(_ id: String, _ file: String, _ token: String) -> Result<(URL, Int64), LocalSendStatus> {
    guard let session else { return .failure(.forbidden) }
    switch session.destination(sessionId: id, fileId: file, token: token) {
    case .success(let url): return .success((url, session.size(of: file) ?? 0))
    case .failure(.wrongSession), .failure(.badToken): return .failure(.forbidden)
    case .failure(.unknownFile): return .failure(.notFound)
    case .failure(.alreadyReceived): return .failure(.conflict)
    case .failure(.tooLarge): return .failure(LocalSendStatus(code: 413))
    }
  }

  private func finished(_ id: String, _ file: String, _ ok: Bool) {
    guard session?.id == id else { return }
    if ok { session?.markReceived(file) }
    guard let current = session, current.isComplete || !ok else { return }
    session = nil
    guard ok else { return }
    IslandFlashCenter.shared.show(
      "Received \(current.receivedCount) file\(current.receivedCount == 1 ? "" : "s")", symbol: "arrow.down.circle.fill",
      tint: .green, detail: "from \(current.sender.alias) · Downloads")
  }

  private func cancelSession(_ id: String) { if session?.id == id { session = nil } }

  /// Asks before anything is written. Brim only accepts files when the user says yes here.
  private func confirm(sender: LocalSendDevice, files: [LocalSendFileMeta]) async -> Bool {
    let total = files.reduce(Int64(0)) { $0 + $1.size }
    let alert = NSAlert()
    alert.messageText = "\(sender.alias) wants to send \(files.count) file\(files.count == 1 ? "" : "s")"
    let names = files.prefix(4).map { LocalSendCodec.safeFileName($0.fileName) }.joined(separator: "\n")
    alert.informativeText = "\(names)\(files.count > 4 ? "\n…" : "")\n\n\(ByteCountFormatter.string(fromByteCount: total, countStyle: .file)) · saved to Downloads"
    alert.addButton(withTitle: L10n.tr("Accept"))
    alert.addButton(withTitle: L10n.tr("Decline"))
    NSApp.activate(ignoringOtherApps: true)
    return alert.runModal() == .alertFirstButtonReturn
  }
}
