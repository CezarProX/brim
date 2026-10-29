import Foundation

/// A parsed HTTP/1.1 request head. Only what the LocalSend API needs.
struct LocalSendRequestHead: Equatable {
  let method: String
  let path: String
  let query: [String: String]
  let headers: [String: String]
  var contentLength: Int { headers["content-length"].flatMap { Int($0) } ?? 0 }
}

enum LocalSendHTTP {
  static let maxHeaderBytes = 16 * 1024
  static let separator = Data("\r\n\r\n".utf8)

  enum ParseResult: Equatable {
    case needMore
    /// The parsed head and the number of bytes it occupied (including the blank line).
    case head(LocalSendRequestHead, consumed: Int)
    case invalid
  }

  static func parseHead(_ buffer: Data) -> ParseResult {
    guard let range = buffer.range(of: separator) else {
      return buffer.count > maxHeaderBytes ? .invalid : .needMore
    }
    guard range.upperBound <= maxHeaderBytes,
      let text = String(data: buffer[buffer.startIndex..<range.lowerBound], encoding: .utf8)
    else { return .invalid }
    var lines = text.components(separatedBy: "\r\n")
    let first = lines.removeFirst().split(separator: " ")
    guard first.count == 3, first[2].hasPrefix("HTTP/1."), let components = URLComponents(string: String(first[1]))
    else { return .invalid }
    var headers: [String: String] = [:]
    for line in lines {
      guard let colon = line.firstIndex(of: ":") else { return .invalid }
      headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
    }
    var query: [String: String] = [:]
    for item in components.queryItems ?? [] { query[item.name] = item.value ?? "" }
    let head = LocalSendRequestHead(
      method: String(first[0]).uppercased(), path: components.path, query: query, headers: headers)
    return .head(head, consumed: buffer.distance(from: buffer.startIndex, to: range.upperBound))
  }

  static func response(status: Int, json: Data? = nil) -> Data {
    let reason: String
    switch status {
    case 200: reason = "OK"
    case 204: reason = "No Content"
    case 400: reason = "Bad Request"
    case 403: reason = "Forbidden"
    case 404: reason = "Not Found"
    case 409: reason = "Conflict"
    case 413: reason = "Payload Too Large"
    case 429: reason = "Too Many Requests"
    default: reason = "Error"
    }
    var head = "HTTP/1.1 \(status) \(reason)\r\nConnection: close\r\n"
    if let json, status != 204 {
      head += "Content-Type: application/json\r\nContent-Length: \(json.count)\r\n\r\n"
      return Data(head.utf8) + json
    }
    head += "Content-Length: 0\r\n\r\n"
    return Data(head.utf8)
  }
}
