import Foundation
import Security

enum LocalSendSendError: Error, LocalizedError, Equatable {
  case noFiles, rejected, busy, tooManyRequests, certificateMismatch, unreachable
  case server(Int)
  case badResponse

  var errorDescription: String? {
    switch self {
    case .noFiles: "There is nothing to send."
    case .rejected: "The other device declined the files."
    case .busy: "The other device is receiving from someone else right now."
    case .tooManyRequests: "The other device says too many requests. Try again in a moment."
    case .certificateMismatch: "That device’s certificate doesn’t match what it announced, so Brim stopped."
    case .unreachable: "Couldn’t reach the device. Check that it is on the same network with LocalSend open."
    case .server(let status): "The other device answered with an error (\(status))."
    case .badResponse: "The other device sent an answer Brim doesn’t understand."
    }
  }

  /// Maps a prepare-upload status to an error; nil for the two success codes.
  static func fromPrepare(status: Int) -> LocalSendSendError? {
    switch status {
    case 200, 204: nil
    case 403: .rejected
    case 409: .busy
    case 429: .tooManyRequests
    default: .server(status)
    }
  }
}

/// Sends files to one LocalSend device (protocol v2): prepare-upload, then one upload per file.
/// HTTPS peers use self-signed certificates, so trust is pinned to the fingerprint the device
/// announced instead of the system store.
final class LocalSendClient: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
  private let device: LocalSendDevice
  private let host: String
  private let sender: LocalSendDevice
  private var session: URLSession?
  private let lock = NSLock()
  private var sentBefore: Int64 = 0
  private var totalBytes: Int64 = 1
  private var progress: (@Sendable (Double) -> Void)?
  private var mismatch = false

  init(device: LocalSendDevice, host: String, sender: LocalSendDevice) {
    self.device = device
    self.host = host
    self.sender = sender
  }

  func send(files urls: [URL], progress: @escaping @Sendable (Double) -> Void) async throws {
    let prepared = try Self.describe(urls)
    guard !prepared.isEmpty else { throw LocalSendSendError.noFiles }
    self.progress = progress
    totalBytes = max(1, prepared.reduce(0) { $0 + $1.meta.size })
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 130
    configuration.waitsForConnectivity = false
    let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    self.session = session
    defer { session.invalidateAndCancel() }

    guard let body = LocalSendCodec.prepareRequest(sender: sender, files: prepared.map(\.meta)) else {
      throw LocalSendSendError.badResponse
    }
    let (data, status) = try await post(LocalSendProtocol.Path.prepareUpload, body: body)
    if let failure = LocalSendSendError.fromPrepare(status: status) { throw failure }
    if status == 204 { return progress(1) }
    guard let response = try? JSONDecoder().decode(LocalSendPrepareResponse.self, from: data) else {
      throw LocalSendSendError.badResponse
    }
    do {
      for file in prepared {
        guard let token = response.files[file.meta.id] else { continue }
        let path = LocalSendCodec.uploadPath(sessionId: response.sessionId, fileId: file.meta.id, token: token)
        try await upload(file.url, path: path)
        lock.withLock { sentBefore += file.meta.size }
      }
    } catch {
      _ = try? await post(LocalSendProtocol.Path.cancel + "?sessionId=\(response.sessionId)", body: Data())
      throw error
    }
    progress(1)
  }

  // MARK: Requests

  private func url(_ path: String) -> URL? {
    URL(string: "\(device.isHTTPS ? "https" : "http")://\(host):\(device.port)\(path)")
  }

  private func post(_ path: String, body: Data) async throws -> (Data, Int) {
    guard let url = url(path), let session else { throw LocalSendSendError.unreachable }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = body
    do {
      let (data, response) = try await session.data(for: request)
      return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    } catch { throw map(error) }
  }

  private func upload(_ file: URL, path: String) async throws {
    guard let url = url(path), let session else { throw LocalSendSendError.unreachable }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
    let status: Int = try await withCheckedThrowingContinuation { continuation in
      let task = session.uploadTask(with: request, fromFile: file) { _, response, error in
        if let error { continuation.resume(throwing: error) } else {
          continuation.resume(returning: (response as? HTTPURLResponse)?.statusCode ?? 0)
        }
      }
      task.resume()
    }
    guard status == 200 else { throw map(nil, status: status) }
  }

  private func map(_ error: Error?, status: Int = 0) -> LocalSendSendError {
    if lock.withLock({ mismatch }) { return .certificateMismatch }
    if error != nil { return .unreachable }
    return status == 403 ? .rejected : .server(status)
  }

  // MARK: Files

  struct Prepared { let url: URL; let meta: LocalSendFileMeta }

  static func describe(_ urls: [URL]) throws -> [Prepared] {
    try urls.compactMap { url in
      var isDirectory: ObjCBool = false
      guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else { return nil }
      let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
      let meta = LocalSendFileMeta(
        id: UUID().uuidString, fileName: url.lastPathComponent, size: size,
        fileType: LocalSendCodec.fileType(forExtension: url.pathExtension), sha256: nil)
      return Prepared(url: url, meta: meta)
    }
  }

  // MARK: Delegate

  func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
    let (before, total) = lock.withLock { (sentBefore, totalBytes) }
    progress?(min(1, Double(before + totalBytesSent) / Double(total)))
  }

  func urlSession(
    _ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
  ) {
    guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
      let trust = challenge.protectionSpace.serverTrust,
      let leaf = (SecTrustCopyCertificateChain(trust) as? [SecCertificate])?.first
    else { return completionHandler(.performDefaultHandling, nil) }
    let hash = LocalSendIdentity.fingerprint(of: leaf)
    if LocalSendCodec.fingerprintMatches(announced: device.fingerprint, certificateHash: hash) {
      completionHandler(.useCredential, URLCredential(trust: trust))
    } else {
      lock.withLock { mismatch = true }
      completionHandler(.cancelAuthenticationChallenge, nil)
    }
  }
}
