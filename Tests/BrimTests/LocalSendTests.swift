import Foundation
import Testing

@testable import Brim

struct LocalSendProtocolTests {
  private let device = LocalSendDevice(
    alias: "Nice Orange", version: "2.0", deviceModel: "Samsung", deviceType: "mobile",
    fingerprint: "abc123", port: 53317, protocol: "https", download: true, announce: true)

  @Test func announcementEncodesTheSpecFieldsAndRoundTrips() throws {
    let data = try #require(LocalSendCodec.announcement(for: device, announce: true))
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(object["alias"] as? String == "Nice Orange")
    #expect(object["version"] as? String == "2.0")
    #expect(object["port"] as? Int == 53317)
    #expect(object["protocol"] as? String == "https")
    #expect(object["announce"] as? Bool == true)
    #expect(LocalSendCodec.decodeAnnouncement(data) == device)
    let reply = try #require(LocalSendCodec.announcement(for: device, announce: false))
    #expect(LocalSendCodec.decodeAnnouncement(reply)?.announce == false)
  }

  @Test func decodesAnAnnouncementFromAnotherImplementation() {
    let json = #"{"alias":"Pixel","version":"2.1","deviceModel":"Google","deviceType":"mobile","fingerprint":"f00","port":53317,"protocol":"http","download":false,"announce":true,"extra":1}"#
    let peer = LocalSendCodec.decodeAnnouncement(Data(json.utf8))
    #expect(peer?.alias == "Pixel" && peer?.isHTTPS == false && peer?.symbol == "iphone")
  }

  @Test func rejectsMalformedOrUnsupportedDatagrams() {
    #expect(LocalSendCodec.decodeAnnouncement(Data("not json".utf8)) == nil)
    #expect(LocalSendCodec.decodeAnnouncement(Data(#"{"alias":"x","version":"1.0","fingerprint":"a","port":1,"protocol":"http"}"#.utf8)) == nil)
    #expect(LocalSendCodec.decodeAnnouncement(Data(#"{"alias":"x","version":"2.0","fingerprint":"","port":1,"protocol":"http"}"#.utf8)) == nil)
    #expect(LocalSendCodec.decodeAnnouncement(Data(#"{"alias":"x","version":"2.0","fingerprint":"a","port":0,"protocol":"http"}"#.utf8)) == nil)
    #expect(LocalSendCodec.decodeAnnouncement(Data(#"{"alias":"x","version":"2.0","fingerprint":"a","port":9,"protocol":"ftp"}"#.utf8)) == nil)
    #expect(LocalSendCodec.decodeAnnouncement(Data(repeating: 0x41, count: 5000)) == nil)
  }

  @Test func prepareRequestHasInfoAndFilesKeyedById() throws {
    let meta = LocalSendFileMeta(id: "f1", fileName: "a.png", size: 12, fileType: "image/png", sha256: nil)
    let data = try #require(LocalSendCodec.prepareRequest(sender: device, files: [meta]))
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let files = try #require(object["files"] as? [String: [String: Any]])
    #expect(files["f1"]?["fileName"] as? String == "a.png")
    #expect(files["f1"]?["size"] as? Int == 12)
    let info = try #require(object["info"] as? [String: Any])
    #expect(info["announce"] == nil)
  }

  @Test func uploadPathEncodesQueryValues() {
    let path = LocalSendCodec.uploadPath(sessionId: "s 1", fileId: "f&1", token: "t=1")
    #expect(path.hasPrefix("/api/localsend/v2/upload?"))
    #expect(!path.contains(" ") && !path.contains("f&1"))
  }

  @Test func prepareStatusesMapToErrors() {
    #expect(LocalSendSendError.fromPrepare(status: 200) == nil)
    #expect(LocalSendSendError.fromPrepare(status: 204) == nil)
    #expect(LocalSendSendError.fromPrepare(status: 403) == .rejected)
    #expect(LocalSendSendError.fromPrepare(status: 409) == .busy)
    #expect(LocalSendSendError.fromPrepare(status: 429) == .tooManyRequests)
    #expect(LocalSendSendError.fromPrepare(status: 500) == .server(500))
  }

  @Test func fingerprintComparisonIgnoresCaseButNotContent() {
    #expect(LocalSendCodec.fingerprintMatches(announced: "ABCD", certificateHash: "abcd"))
    #expect(!LocalSendCodec.fingerprintMatches(announced: "abcd", certificateHash: "abce"))
    #expect(!LocalSendCodec.fingerprintMatches(announced: "", certificateHash: ""))
  }

  @Test func fileNamesCannotEscapeTheDownloadsFolder() {
    #expect(LocalSendCodec.safeFileName("../../.ssh/authorized_keys") == "authorized_keys")
    #expect(LocalSendCodec.safeFileName("..\\..\\evil.exe") == "evil.exe")
    #expect(LocalSendCodec.safeFileName("..") == "file")
    #expect(LocalSendCodec.safeFileName("") == "file")
    #expect(LocalSendCodec.safeFileName("photo.jpg") == "photo.jpg")
  }
}

struct LocalSendReceiveSessionTests {
  private let sender = LocalSendDevice(
    alias: "Phone", version: "2.0", deviceModel: nil, deviceType: "mobile", fingerprint: "x", port: 1, protocol: "https", download: nil, announce: nil)
  private let folder = URL(fileURLWithPath: "/tmp/qs-downloads")

  private func make(_ names: [String], existing: Set<String> = []) -> LocalSendReceiveSession {
    var counter = 0
    return LocalSendReceiveSession(
      sender: sender,
      files: names.enumerated().map { LocalSendFileMeta(id: "f\($0.offset)", fileName: $0.element, size: 10, fileType: "x", sha256: nil) },
      folder: folder, exists: { existing.contains($0.lastPathComponent) },
      makeToken: { counter += 1; return "tok\(counter)" }, id: "S")
  }

  @Test func destinationsStayInsideTheFolderAndStayUnique() {
    let session = make(["../../etc/passwd", "a.txt", "a.txt"], existing: ["a.txt"])
    let paths = Set(session.files.values.map(\.destination.path))
    #expect(paths.count == 3)
    #expect(paths.allSatisfy { $0.hasPrefix("/private/tmp/qs-downloads/") || $0.hasPrefix("/tmp/qs-downloads/") })
    #expect(paths.contains { $0.hasSuffix("/a 2.txt") } && paths.contains { $0.hasSuffix("/a 3.txt") })
  }

  @Test func uploadsNeedTheRightSessionFileAndToken() {
    var session = make(["a.txt"])
    #expect(session.destination(sessionId: "other", fileId: "f0", token: "tok1") == .failure(.wrongSession))
    #expect(session.destination(sessionId: "S", fileId: "nope", token: "tok1") == .failure(.unknownFile))
    #expect(session.destination(sessionId: "S", fileId: "f0", token: "tok2") == .failure(.badToken))
    #expect((try? session.destination(sessionId: "S", fileId: "f0", token: "tok1").get()) != nil)
    session.markReceived("f0")
    #expect(session.destination(sessionId: "S", fileId: "f0", token: "tok1") == .failure(.alreadyReceived))
    #expect(session.isComplete && session.receivedCount == 1)
  }
}

struct LocalSendHTTPTests {
  @Test func parsesRequestHeadAndQuery() {
    let raw = "POST /api/localsend/v2/upload?sessionId=a&fileId=b&token=c%20d HTTP/1.1\r\nHost: x\r\nContent-Length: 5\r\n\r\nhello"
    guard case .head(let head, let consumed) = LocalSendHTTP.parseHead(Data(raw.utf8)) else {
      Issue.record("expected a head")
      return
    }
    #expect(head.method == "POST" && head.path == "/api/localsend/v2/upload")
    #expect(head.query == ["sessionId": "a", "fileId": "b", "token": "c d"])
    #expect(head.contentLength == 5)
    #expect(consumed == raw.utf8.count - 5)
  }

  @Test func waitsForMoreAndRejectsGarbage() {
    #expect(LocalSendHTTP.parseHead(Data("POST /x HTTP/1.1\r\nHost".utf8)) == .needMore)
    #expect(LocalSendHTTP.parseHead(Data("nonsense\r\n\r\n".utf8)) == .invalid)
    #expect(LocalSendHTTP.parseHead(Data(repeating: 0x41, count: 20_000)) == .invalid)
    #expect(LocalSendHTTP.parseHead(Data("GET / HTTP/1.1\r\nbadheader\r\n\r\n".utf8)) == .invalid)
  }

  @Test func responsesCarryLengthAndNoBodyFor204() {
    let json = Data("{}".utf8)
    let ok = String(decoding: LocalSendHTTP.response(status: 200, json: json), as: UTF8.self)
    #expect(ok.hasPrefix("HTTP/1.1 200 OK") && ok.contains("Content-Length: 2") && ok.hasSuffix("{}"))
    let none = String(decoding: LocalSendHTTP.response(status: 204, json: json), as: UTF8.self)
    #expect(none.contains("Content-Length: 0") && !none.contains("{}"))
  }
}

/// End to end on loopback: a real certificate, the HTTPS server, and the client with pinning.
@Suite(.serialized)
struct LocalSendLoopbackTests {
  private final class Box: @unchecked Sendable {
    var session: LocalSendReceiveSession?
    let lock = NSLock()
  }

  @Test func clientDeliversAFileToTheServerAndPinsTheCertificate() async throws {
    let material = try await LocalSendIdentity.load()
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("qs-ls-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let source = folder.appendingPathComponent("hello.txt")
    let payload = Data((0..<300_000).map { UInt8($0 % 251) })
    try payload.write(to: source)
    let inbox = folder.appendingPathComponent("inbox")
    try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)

    let me = LocalSendModel.makeDevice(alias: "Test Receiver", fingerprint: material.fingerprint, port: 0)
    let box = Box()
    let handlers = LocalSendServerHandlers(
      info: { me }, peerSeen: { _, _ in },
      prepare: { request in
        let session = LocalSendReceiveSession(sender: request.info, files: Array(request.files.values), folder: inbox)
        box.lock.withLock { box.session = session }
        return .success(LocalSendPrepareResponse(sessionId: session.id, files: session.tokens))
      },
      destination: { id, file, token in
        guard let session = box.lock.withLock({ box.session }) else { return .failure(.forbidden) }
        switch session.destination(sessionId: id, fileId: file, token: token) {
        case .success(let url): return .success((url, session.size(of: file) ?? 0))
        case .failure: return .failure(.forbidden)
        }
      },
      fileFinished: { _, _, _ in }, cancel: { _ in })
    let server = LocalSendServer(handlers: handlers)
    let port = try await server.start(identity: material.identity)
    defer { server.stop() }

    var target = me
    target.port = Int(port)
    let sender = LocalSendModel.makeDevice(alias: "Test Sender", fingerprint: "sender", port: 1)
    let client = LocalSendClient(device: target, host: "127.0.0.1", sender: sender)
    try await client.send(files: [source]) { _ in }
    let received = try Data(contentsOf: inbox.appendingPathComponent("hello.txt"))
    #expect(received == payload)

    // A device announcing a different fingerprint must not be trusted.
    var impostor = target
    impostor.fingerprint = "0000"
    let wrong = LocalSendClient(device: impostor, host: "127.0.0.1", sender: sender)
    await #expect(throws: LocalSendSendError.certificateMismatch) {
      try await wrong.send(files: [source]) { _ in }
    }
  }
}
