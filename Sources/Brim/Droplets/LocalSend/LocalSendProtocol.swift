import Foundation

/// The open LocalSend protocol, version 2: message types and their JSON encoding.
/// https://github.com/localsend/protocol
enum LocalSendProtocol {
  static let multicastAddress = "224.0.0.167"
  static let port: UInt16 = 53317
  static let version = "2.0"
  static let apiBase = "/api/localsend/v2"

  enum Path {
    static let register = apiBase + "/register"
    static let info = apiBase + "/info"
    static let prepareUpload = apiBase + "/prepare-upload"
    static let upload = apiBase + "/upload"
    static let cancel = apiBase + "/cancel"
  }
}

/// A device as announced over multicast or exchanged over HTTP.
struct LocalSendDevice: Codable, Equatable, Identifiable, Sendable {
  var alias: String
  var version: String
  var deviceModel: String?
  var deviceType: String?
  var fingerprint: String
  var port: Int
  var `protocol`: String
  var download: Bool?
  /// True on a multicast announcement that wants a reply; false on the reply itself.
  var announce: Bool?

  var id: String { fingerprint }
  var isHTTPS: Bool { `protocol`.lowercased() == "https" }

  /// SF Symbol for the device kind.
  var symbol: String {
    switch deviceType {
    case "mobile": "iphone"
    case "web": "globe"
    case "headless", "server": "server.rack"
    default: "laptopcomputer"
    }
  }
}

struct LocalSendFileMeta: Codable, Equatable, Sendable {
  var id: String
  var fileName: String
  var size: Int64
  var fileType: String
  var sha256: String?
}

struct LocalSendPrepareRequest: Codable, Equatable, Sendable {
  var info: LocalSendDevice
  var files: [String: LocalSendFileMeta]
}

struct LocalSendPrepareResponse: Codable, Equatable, Sendable {
  var sessionId: String
  /// File id to upload token.
  var files: [String: String]
}

enum LocalSendCodec {
  private static var encoder: JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return encoder
  }

  static func encode<T: Encodable>(_ value: T) -> Data? { try? encoder.encode(value) }

  /// Decodes a multicast datagram. Returns nil for anything that is not a well-formed device
  /// message of a protocol version this code understands (major version 2).
  static func decodeAnnouncement(_ data: Data) -> LocalSendDevice? {
    guard data.count < 4096, let device = try? JSONDecoder().decode(LocalSendDevice.self, from: data),
      device.version.hasPrefix("2."), !device.fingerprint.isEmpty, (1...65535).contains(device.port),
      ["http", "https"].contains(device.protocol.lowercased())
    else { return nil }
    return device
  }

  /// Our own announcement or reply.
  static func announcement(for device: LocalSendDevice, announce: Bool) -> Data? {
    var copy = device
    copy.announce = announce
    return encode(copy)
  }

  /// A prepare-upload body for files with known sizes.
  static func prepareRequest(sender: LocalSendDevice, files: [LocalSendFileMeta]) -> Data? {
    var info = sender
    info.announce = nil
    return encode(
      LocalSendPrepareRequest(info: info, files: Dictionary(uniqueKeysWithValues: files.map { ($0.id, $0) })))
  }

  /// MIME-ish type string LocalSend shows ("image", "video", ... or a full MIME type).
  static func fileType(forExtension ext: String) -> String {
    switch ext.lowercased() {
    case "png", "jpg", "jpeg", "gif", "heic", "webp", "tiff": "image/\(ext.lowercased() == "jpg" ? "jpeg" : ext.lowercased())"
    case "mp4", "mov", "m4v": "video/\(ext.lowercased() == "mov" ? "quicktime" : "mp4")"
    case "mp3", "m4a", "wav", "aac": "audio/\(ext.lowercased() == "mp3" ? "mpeg" : ext.lowercased())"
    case "pdf": "application/pdf"
    case "txt", "md": "text/plain"
    default: "application/octet-stream"
    }
  }

  /// Query for the upload endpoint. Values are percent-encoded.
  static func uploadPath(sessionId: String, fileId: String, token: String) -> String {
    var components = URLComponents()
    components.queryItems = [
      URLQueryItem(name: "sessionId", value: sessionId), URLQueryItem(name: "fileId", value: fileId),
      URLQueryItem(name: "token", value: token),
    ]
    return LocalSendProtocol.Path.upload + "?" + (components.percentEncodedQuery ?? "")
  }

  /// Whether a certificate's SHA-256 matches the fingerprint a device announced.
  static func fingerprintMatches(announced: String, certificateHash: String) -> Bool {
    !announced.isEmpty && announced.lowercased() == certificateHash.lowercased()
  }

  /// A file name that is safe to create inside a folder: no directories, no dot-dot, not hidden-only.
  static func safeFileName(_ name: String) -> String {
    let last = name.replacingOccurrences(of: "\\", with: "/").split(separator: "/").last.map(String.init) ?? ""
    let cleaned = last.unicodeScalars.filter { $0.value >= 32 && $0.value != 127 }.map(String.init).joined()
      .trimmingCharacters(in: .whitespaces)
    if cleaned.isEmpty || cleaned == "." || cleaned == ".." { return "file" }
    return String(cleaned.prefix(200))
  }
}
