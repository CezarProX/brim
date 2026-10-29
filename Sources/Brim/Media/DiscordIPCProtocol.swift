import Foundation

/// Discord's local RPC framing: `[opcode: Int32 LE][length: Int32 LE][UTF-8 JSON]`.
enum DiscordIPCProtocol {
  enum Opcode: Int32 { case handshake = 0, frame = 1, close = 2, ping = 3, pong = 4 }
  static let maxPayload = 64 * 1024

  static func frame(_ opcode: Opcode, json: Data) -> Data {
    var data = Data()
    withUnsafeBytes(of: opcode.rawValue.littleEndian) { data.append(contentsOf: $0) }
    withUnsafeBytes(of: Int32(json.count).littleEndian) { data.append(contentsOf: $0) }
    data.append(json)
    return data
  }

  static func handshake(clientID: String) throws -> Data {
    frame(.handshake, json: try JSONSerialization.data(withJSONObject: ["v": 1, "client_id": clientID], options: [.sortedKeys]))
  }

  /// Parses one frame from the front of `buffer`. Returns nil until a whole frame has arrived.
  static func parse(_ buffer: Data) throws -> (opcode: Opcode, payload: Data, consumed: Int)? {
    guard buffer.count >= 8 else { return nil }
    let base = buffer.startIndex
    let rawOp = buffer[base..<base + 4].withUnsafeBytes { Int32(littleEndian: $0.loadUnaligned(as: Int32.self)) }
    let length = buffer[base + 4..<base + 8].withUnsafeBytes { Int32(littleEndian: $0.loadUnaligned(as: Int32.self)) }
    guard length >= 0, Int(length) <= maxPayload, let opcode = Opcode(rawValue: rawOp) else { throw DiscordError.badFrame }
    guard buffer.count >= 8 + Int(length) else { return nil }
    return (opcode, Data(buffer[base + 8..<base + 8 + Int(length)]), 8 + Int(length))
  }

  /// Discord client ids are numeric snowflakes.
  static func isValidClientID(_ value: String) -> Bool {
    (15...22).contains(value.count) && value.allSatisfy(\.isASCII) && value.allSatisfy(\.isNumber)
  }

  /// Discord needs 2...128 characters in each text field.
  static func clean(_ text: String) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let clipped = String(trimmed.prefix(128))
    return clipped.count < 2 ? clipped + "  " : clipped
  }

  /// A "Listening to" activity. `elapsed`/`duration` produce Discord's live progress bar.
  static func setActivity(
    title: String, artist: String, album: String, elapsed: TimeInterval, duration: TimeInterval,
    isPlaying: Bool, pid: Int32, nonce: String, now: Date = .now
  ) throws -> Data {
    var activity: [String: Any] = [
      "type": 2, "details": clean(title), "state": clean(artist.isEmpty ? "Unknown artist" : artist),
    ]
    if isPlaying, duration > 0 {
      let start = now.timeIntervalSince1970 - elapsed
      activity["timestamps"] = ["start": Int(start), "end": Int(start + duration)]
    }
    if !album.isEmpty { activity["assets"] = ["large_text": clean(album)] }
    let body: [String: Any] = [
      "cmd": "SET_ACTIVITY", "nonce": nonce,
      "args": ["pid": Int(pid), "activity": (isPlaying ? activity : NSNull()) as Any],
    ]
    return frame(.frame, json: try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]))
  }

  static func clearActivity(pid: Int32, nonce: String) throws -> Data {
    let body: [String: Any] = ["cmd": "SET_ACTIVITY", "nonce": nonce, "args": ["pid": Int(pid), "activity": NSNull()]]
    return frame(.frame, json: try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]))
  }
}

enum DiscordError: Error, Equatable { case badFrame, notRunning, badClientID, io }
