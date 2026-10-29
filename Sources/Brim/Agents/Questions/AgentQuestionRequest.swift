import Foundation

/// One choice on a question card.
struct AgentQuestionOption: Equatable, Sendable {
  let label: String
  let detail: String?
}

/// A question or approval an agent sends to the island. Everything arrives from a local socket, so
/// `parse` validates size, schema and lengths and refuses anything it does not understand.
struct AgentQuestionRequest: Equatable, Sendable {
  enum Kind: String, Sendable { case question, approval }

  enum Limits {
    static let maxBytes = 64 * 1024
    static let maxQuestion = 600
    static let maxLabel = 120
    static let maxDetail = 240
    static let maxOptions = 4
    static let maxPath = 1024
    static let maxSession = 128
    static let defaultTimeout: TimeInterval = 100
    static let timeoutRange: ClosedRange<TimeInterval> = 5...600
  }

  enum ParseError: Error, Equatable {
    case tooLarge, malformed, unsupportedVersion, unknownAgent, unknownKind
    case missing(String)
    case tooManyOptions
  }

  let kind: Kind
  let agent: CodingAgentSession.Tool
  let cwd: String
  let sessionID: String
  /// The agent's process id (the hook's parent), used only to find the app to bring forward.
  let processID: Int32?
  let header: String?
  let question: String
  let options: [AgentQuestionOption]
  let multiSelect: Bool
  let allowsText: Bool
  let timeout: TimeInterval

  /// Folder name shown under the agent's name.
  var project: String { cwd.isEmpty ? "" : (cwd as NSString).lastPathComponent }

  static func parse(_ data: Data) throws -> AgentQuestionRequest {
    guard data.count <= Limits.maxBytes else { throw ParseError.tooLarge }
    guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { throw ParseError.malformed }
    if let version = object["v"] { guard (version as? Int) == 1 else { throw ParseError.unsupportedVersion } }
    guard let agentID = object["agent"] as? String else { throw ParseError.missing("agent") }
    guard let agent = CodingAgentSession.Tool.allCases.first(where: { $0.settingsID == agentID }) else { throw ParseError.unknownAgent }
    let kind: Kind
    if let raw = object["kind"] as? String {
      guard let parsed = Kind(rawValue: raw) else { throw ParseError.unknownKind }
      kind = parsed
    } else { kind = .question }
    guard let rawQuestion = object["question"] as? String else { throw ParseError.missing("question") }
    let question = clean(rawQuestion, limit: Limits.maxQuestion)
    guard !question.isEmpty else { throw ParseError.missing("question") }
    guard let rawSession = object["sessionId"] as? String else { throw ParseError.missing("sessionId") }
    let session = clean(rawSession, limit: Limits.maxSession, multiline: false)
    guard !session.isEmpty else { throw ParseError.missing("sessionId") }

    var options: [AgentQuestionOption] = []
    if let list = object["options"] as? [Any] {
      guard list.count <= Limits.maxOptions else { throw ParseError.tooManyOptions }
      for item in list {
        if let label = item as? String {
          let text = clean(label, limit: Limits.maxLabel, multiline: false)
          if !text.isEmpty { options.append(AgentQuestionOption(label: text, detail: nil)) }
        } else if let dict = item as? [String: Any], let label = dict["label"] as? String {
          let text = clean(label, limit: Limits.maxLabel, multiline: false)
          let detail = (dict["description"] as? String).map { clean($0, limit: Limits.maxDetail, multiline: false) }
          if !text.isEmpty { options.append(AgentQuestionOption(label: text, detail: detail?.isEmpty == false ? detail : nil)) }
        } else { throw ParseError.malformed }
      }
    }
    let timeout = (object["timeoutSeconds"] as? Double).map { min(max($0, Limits.timeoutRange.lowerBound), Limits.timeoutRange.upperBound) }
      ?? Limits.defaultTimeout
    let header = (object["header"] as? String).map { clean($0, limit: 40, multiline: false) }
    return AgentQuestionRequest(
      kind: kind, agent: agent, cwd: clean((object["cwd"] as? String) ?? "", limit: Limits.maxPath, multiline: false),
      sessionID: session, processID: (object["pid"] as? Int).flatMap { $0 > 1 ? Int32(exactly: $0) : nil },
      header: header?.isEmpty == false ? header : nil, question: question, options: options,
      multiSelect: kind == .question && (object["multiSelect"] as? Bool ?? false),
      allowsText: kind == .question && (object["allowText"] as? Bool ?? true), timeout: timeout)
  }

  /// Drops control characters (keeping newline and tab when allowed), trims, and clips to `limit` characters.
  static func clean(_ text: String, limit: Int, multiline: Bool = true) -> String {
    let kept = text.unicodeScalars.filter { scalar in
      if scalar == "\n" || scalar == "\t" { return multiline }
      // Bidi overrides and isolates can make a command read differently from what runs.
      if (0x202A...0x202E).contains(scalar.value) || (0x2066...0x2069).contains(scalar.value)
        || scalar.value == 0x200E || scalar.value == 0x200F || scalar.value == 0x061C { return false }
      return !(scalar.value < 0x20 || scalar.value == 0x7F)
    }
    var result = String(String.UnicodeScalarView(kept)).trimmingCharacters(in: .whitespacesAndNewlines)
    if result.count > limit { result = String(result.prefix(limit - 1)) + "\u{2026}" }
    return result
  }
}

/// What the island sends back over the socket.
struct AgentQuestionResponse: Equatable, Sendable {
  enum Status: String, Sendable {
    case answered, allow, deny
    /// Nothing was decided; the agent should ask in its own terminal as usual.
    case timeout, dismissed, superseded, busy, disabled, invalid
  }

  let status: Status
  let answer: String?

  init(_ status: Status, answer: String? = nil) {
    self.status = status
    self.answer = answer
  }

  /// True when the user actually decided something.
  var isDecision: Bool { status == .answered || status == .allow || status == .deny }

  func wireData() -> Data {
    var object: [String: Any] = ["v": 1, "status": status.rawValue]
    if let answer { object["answer"] = answer }
    let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data("{}".utf8)
    return data + Data([0x0A])
  }

  static func parse(_ data: Data) -> AgentQuestionResponse? {
    guard data.count <= AgentQuestionRequest.Limits.maxBytes,
      let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
      let raw = object["status"] as? String, let status = Status(rawValue: raw)
    else { return nil }
    return AgentQuestionResponse(status, answer: object["answer"] as? String)
  }
}
