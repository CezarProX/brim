import Foundation

/// One accepted incoming transfer: who sent it, what they may upload, and where it goes.
/// Pure bookkeeping (no sockets), so the security-relevant checks are unit tested.
struct LocalSendReceiveSession {
  struct Expected: Equatable {
    let meta: LocalSendFileMeta
    let token: String
    let destination: URL
    var received = false
  }

  let id: String
  let sender: LocalSendDevice
  private(set) var files: [String: Expected]

  enum UploadError: Error, Equatable {
    case wrongSession, unknownFile, badToken, alreadyReceived, tooLarge
  }

  /// Builds a session for the files a sender announced. File names are sanitized and made
  /// unique inside `folder`; `exists` lets tests avoid touching the disk.
  init(
    sender: LocalSendDevice, files metas: [LocalSendFileMeta], folder: URL,
    exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) },
    makeToken: () -> String = { UUID().uuidString }, id: String = UUID().uuidString
  ) {
    self.id = id
    self.sender = sender
    var claimed = Set<String>()
    var built: [String: Expected] = [:]
    for meta in metas.sorted(by: { $0.id < $1.id }) {
      var destination = Self.unique(
        folder: folder, name: LocalSendCodec.safeFileName(meta.fileName), exists: { exists($0) || claimed.contains($0.path) })
      destination = destination.standardizedFileURL
      claimed.insert(destination.path)
      built[meta.id] = Expected(meta: meta, token: makeToken(), destination: destination)
    }
    self.files = built
  }

  var tokens: [String: String] { files.mapValues(\.token) }
  var isComplete: Bool { files.values.allSatisfy(\.received) }
  var receivedCount: Int { files.values.filter(\.received).count }

  /// Validates an upload request and returns where its body should be written.
  func destination(sessionId: String, fileId: String, token: String) -> Result<URL, UploadError> {
    guard sessionId == id else { return .failure(.wrongSession) }
    guard let expected = files[fileId] else { return .failure(.unknownFile) }
    guard Self.constantTimeEqual(token, expected.token) else { return .failure(.badToken) }
    guard !expected.received else { return .failure(.alreadyReceived) }
    return .success(expected.destination)
  }

  /// The declared size for a file; uploads larger than this are refused.
  func size(of fileId: String) -> Int64? { files[fileId]?.meta.size }

  mutating func markReceived(_ fileId: String) { files[fileId]?.received = true }

  static func unique(folder: URL, name: String, exists: (URL) -> Bool) -> URL {
    var candidate = folder.appendingPathComponent(name)
    guard exists(candidate) else { return candidate }
    let base = (name as NSString).deletingPathExtension
    let ext = (name as NSString).pathExtension
    var counter = 2
    repeat {
      candidate = folder.appendingPathComponent(ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)")
      counter += 1
    } while exists(candidate)
    return candidate
  }

  private static func constantTimeEqual(_ a: String, _ b: String) -> Bool {
    let x = Array(a.utf8), y = Array(b.utf8)
    guard x.count == y.count else { return false }
    return zip(x, y).reduce(0) { $0 | ($1.0 ^ $1.1) } == 0
  }
}
