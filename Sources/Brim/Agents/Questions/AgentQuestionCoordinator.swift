import AppKit
import Combine

/// Owns the pending agent questions: queues them, shows the card for the head, enforces timeouts and
/// hands each answer back to the waiting socket connection.
@MainActor
final class AgentQuestionCoordinator: ObservableObject {
  static let shared = AgentQuestionCoordinator()

  @Published private(set) var queue = AgentQuestionQueue()
  var isEnabled: () -> Bool = { AppSettings.shared.agentQuestionsEnabled }
  var now: () -> Date = { Date() }
  /// Brings the agent's app forward; replaced in tests.
  var jumper: (AgentQuestionRequest) -> Bool = { AgentQuestionJump.open($0) }

  private var waiters: [UUID: CheckedContinuation<AgentQuestionResponse, Never>] = [:]
  private var expiryTask: Task<Void, Never>?

  var current: AgentQuestionQueue.Entry? { queue.current }

  /// Shows the request and waits for the user. Always returns; cancelling the task withdraws the card.
  func ask(_ request: AgentQuestionRequest) async -> AgentQuestionResponse {
    guard isEnabled() else { return AgentQuestionResponse(.disabled) }
    let id = UUID()
    return await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        let result = queue.offer(request, id: id, now: now())
        guard result.accepted else { continuation.resume(returning: AgentQuestionResponse(.busy)); return }
        waiters[id] = continuation
        if let old = result.replaced { finish(old.id, AgentQuestionResponse(.superseded), alreadyRemoved: true) }
        scheduleExpiry()
        if Task.isCancelled { finish(id, AgentQuestionResponse(.dismissed)) }
      }
    } onCancel: {
      Task { @MainActor in self.finish(id, AgentQuestionResponse(.dismissed)) }
    }
  }

  // MARK: User actions

  func choose(_ labels: [String]) {
    guard let entry = current, !labels.isEmpty else { return }
    finish(entry.id, AgentQuestionResponse(.answered, answer: labels.joined(separator: ", ")))
  }

  func reply(_ text: String) {
    let clean = AgentQuestionRequest.clean(text, limit: AgentQuestionRequest.Limits.maxQuestion)
    guard let entry = current, entry.request.allowsText, !clean.isEmpty else { return }
    finish(entry.id, AgentQuestionResponse(.answered, answer: clean))
  }

  func decide(allow: Bool) {
    guard let entry = current, entry.request.kind == .approval else { return }
    finish(entry.id, AgentQuestionResponse(allow ? .allow : .deny))
  }

  /// The close button: the agent falls back to asking in its terminal.
  func dismiss() {
    guard let entry = current else { return }
    finish(entry.id, AgentQuestionResponse(.dismissed))
  }

  /// Brings the agent's terminal forward and leaves the card up.
  func jumpToTerminal() {
    guard let entry = current else { return }
    _ = jumper(entry.request)
  }

  /// Times out every card whose deadline has passed.
  func sweep() {
    for entry in queue.expire(now: now()) { finish(entry.id, AgentQuestionResponse(.timeout), alreadyRemoved: true) }
    scheduleExpiry()
  }

  /// Answers every pending card as dismissed (feature switched off, app quitting).
  func dismissAll() {
    for entry in queue.entries { finish(entry.id, AgentQuestionResponse(.dismissed)) }
  }

  // MARK: Plumbing

  private func finish(_ id: UUID, _ response: AgentQuestionResponse, alreadyRemoved: Bool = false) {
    if !alreadyRemoved { queue.resolve(id) }
    waiters.removeValue(forKey: id)?.resume(returning: response)
    scheduleExpiry()
  }

  private func scheduleExpiry() {
    expiryTask?.cancel()
    guard let deadline = queue.nextDeadline else { return }
    let delay = max(0.05, deadline.timeIntervalSince(now()))
    expiryTask = Task { [weak self] in
      try? await Task.sleep(for: .seconds(delay))
      guard !Task.isCancelled else { return }
      self?.sweep()
    }
  }
}

/// Brings forward the app that hosts an agent session.
enum AgentQuestionJump {
  @MainActor
  static func open(_ request: AgentQuestionRequest) -> Bool {
    if let pid = request.processID,
      let appPID = CodingAgentLocator.owningApp(
        of: pid, parent: CodingAgentLocator.parentProcess,
        isApp: { NSRunningApplication(processIdentifier: $0)?.activationPolicy == .regular }),
      let app = NSRunningApplication(processIdentifier: appPID)
    {
      return app.activate(options: [])
    }
    var bundles = AgentBrand.bundleIDs(request.agent)
    if [.claude, .codex, .openCode].contains(request.agent) { bundles += AgentBrand.terminalBundleIDs }
    for bundle in bundles {
      if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first { return app.activate(options: []) }
    }
    return false
  }
}
