import Foundation

/// The command Claude Code runs for its hooks (`Brim --agent-hook`): it reads the hook JSON on
/// stdin, asks the running app over the local socket, and prints Claude Code's documented reply.
/// No output with exit 0 means "no opinion": Claude Code then asks in the terminal as it always did.
enum AgentHook {
  struct Output: Equatable {
    var stdout: Data?
    var exitCode: Int32 = 0
  }

  /// Sends a request to the app; nil when the app is not running or the feature is off.
  typealias Transport = (Data) -> AgentQuestionResponse?

  static let maxInput = 1_000_000
  /// Tools whose approval needs the terminal (a plan to read), and the question tool itself.
  static let approvalSkipped: Set<String> = ["AskUserQuestion", "ExitPlanMode"]

  static func respond(to input: Data, processID: Int32?, transport: Transport) -> Output {
    guard input.count <= maxInput, let event = (try? JSONSerialization.jsonObject(with: input)) as? [String: Any],
      let name = event["hook_event_name"] as? String, let tool = event["tool_name"] as? String
    else { return Output() }
    let context = Context(
      cwd: (event["cwd"] as? String) ?? "", sessionID: (event["session_id"] as? String) ?? "", processID: processID)
    let toolInput = (event["tool_input"] as? [String: Any]) ?? [:]
    switch (name, tool) {
    case ("PreToolUse", "AskUserQuestion"):
      return answerQuestions(toolInput, context, transport)
    case ("PermissionRequest", _) where !approvalSkipped.contains(tool):
      return decideApproval(tool: tool, input: toolInput, context, transport)
    default:
      return Output()
    }
  }

  private struct Context {
    let cwd: String
    let sessionID: String
    let processID: Int32?
  }

  // MARK: AskUserQuestion

  private static func answerQuestions(_ toolInput: [String: Any], _ context: Context, _ transport: Transport) -> Output {
    guard let questions = toolInput["questions"] as? [[String: Any]], !questions.isEmpty, questions.count <= 4 else { return Output() }
    var answers = (toolInput["answers"] as? [String: String]) ?? [:]
    for item in questions {
      guard let text = item["question"] as? String else { return Output() }
      let options = ((item["options"] as? [[String: Any]]) ?? []).compactMap { option -> [String: Any]? in
        guard let label = option["label"] as? String else { return nil }
        var entry: [String: Any] = ["label": label]
        if let detail = option["description"] as? String { entry["description"] = detail }
        return entry
      }
      var payload: [String: Any] = [
        "v": 1, "kind": "question", "agent": "claude", "cwd": context.cwd, "sessionId": context.sessionID,
        "question": text, "options": options, "multiSelect": (item["multiSelect"] as? Bool) ?? false,
      ]
      if let header = item["header"] as? String { payload["header"] = header }
      if let pid = context.processID { payload["pid"] = Int(pid) }
      guard let data = try? JSONSerialization.data(withJSONObject: payload),
        let response = transport(data), response.status == .answered, let answer = response.answer
      else { return Output() }  // anything but a real answer: let the terminal ask everything
      answers[text] = answer
    }
    var updated = toolInput
    updated["answers"] = answers
    return Output(stdout: encode([
      "hookSpecificOutput": [
        "hookEventName": "PreToolUse", "permissionDecision": "allow",
        "permissionDecisionReason": "Answered from the Brim island", "updatedInput": updated,
      ]
    ]))
  }

  // MARK: Approvals

  private static func decideApproval(tool: String, input: [String: Any], _ context: Context, _ transport: Transport) -> Output {
    var payload: [String: Any] = [
      "v": 1, "kind": "approval", "agent": "claude", "cwd": context.cwd, "sessionId": context.sessionID,
      "question": "Allow \(tool)?", "header": tool, "options": [] as [Any],
    ]
    let summary = summarize(tool: tool, input: input)
    // Allow must never be one click away from a command the card shows only in part.
    guard fitsOnCard(summary) else { return Output() }
    if !summary.isEmpty { payload["question"] = "Allow \(tool)? \(summary)" }
    if let pid = context.processID { payload["pid"] = Int(pid) }
    guard let data = try? JSONSerialization.data(withJSONObject: payload), let response = transport(data) else { return Output() }
    switch response.status {
    case .allow:
      return Output(stdout: encode(["hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": ["behavior": "allow"]]]))
    case .deny:
      return Output(stdout: encode([
        "hookSpecificOutput": [
          "hookEventName": "PermissionRequest",
          "decision": ["behavior": "deny", "message": "Denied from the Brim island"],
        ]
      ]))
    default:
      return Output()
    }
  }

  /// Whether the approval card can show `summary` whole and readably: short, at most four lines,
  /// and free of invisible format characters such as zero-width spaces. Anything else is left to
  /// Claude Code's terminal prompt, which shows the full command.
  static func fitsOnCard(_ summary: String) -> Bool {
    guard summary.count <= 300 else { return false }
    guard summary.split(separator: "\n", omittingEmptySubsequences: false).count <= 4 else { return false }
    return !summary.unicodeScalars.contains { $0.properties.generalCategory == .format }
  }

  /// The one detail worth showing for a tool call: the command, the file, or a clipped dump.
  static func summarize(tool: String, input: [String: Any]) -> String {
    for key in ["command", "file_path", "path", "url", "pattern"] {
      if let value = input[key] as? String, !value.isEmpty { return value }
    }
    guard !input.isEmpty, let data = try? JSONSerialization.data(withJSONObject: input, options: [.sortedKeys]),
      let text = String(data: data, encoding: .utf8)
    else { return "" }
    return text
  }

  private static func encode(_ object: [String: Any]) -> Data? {
    try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
  }

  // MARK: Process entry

  /// Runs as `Brim --agent-hook`. Never blocks Claude Code on failure.
  static func runAndExit() -> Never {
    let input = FileHandle.standardInput.readData(ofLength: maxInput + 1)
    let output = respond(to: input, processID: getppid()) { payload in
      AgentQuestionSocket.request(payload, waitSeconds: Int(AgentQuestionRequest.Limits.timeoutRange.upperBound) + 10)
    }
    if let data = output.stdout { FileHandle.standardOutput.write(data) }
    exit(output.exitCode)
  }
}
