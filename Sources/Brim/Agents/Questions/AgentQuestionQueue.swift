import Foundation

/// The pending questions, oldest first. The head is the one on screen. A session has at most one
/// pending entry: a newer request from the same session replaces the older one, because an agent
/// that asks again has abandoned the first (it was answered in the terminal, or the hook was killed).
struct AgentQuestionQueue: Equatable {
  struct Entry: Identifiable, Equatable {
    let id: UUID
    let request: AgentQuestionRequest
    let deadline: Date
  }

  static let capacity = 8

  private(set) var entries: [Entry] = []

  var current: Entry? { entries.first }
  /// Cards waiting behind the one on screen.
  var waiting: Int { max(0, entries.count - 1) }
  var nextDeadline: Date? { entries.map(\.deadline).min() }

  /// Adds a request. Returns the entry it replaced (same session), or nil when it was appended;
  /// `accepted` is false when the queue is full.
  mutating func offer(_ request: AgentQuestionRequest, id: UUID = UUID(), now: Date) -> (accepted: Bool, replaced: Entry?) {
    let entry = Entry(id: id, request: request, deadline: now.addingTimeInterval(request.timeout))
    if let index = entries.firstIndex(where: { $0.request.agent == request.agent && $0.request.sessionID == request.sessionID }) {
      let old = entries[index]
      entries[index] = entry
      return (true, old)
    }
    guard entries.count < Self.capacity else { return (false, nil) }
    entries.append(entry)
    return (true, nil)
  }

  @discardableResult
  mutating func resolve(_ id: UUID) -> Entry? {
    guard let index = entries.firstIndex(where: { $0.id == id }) else { return nil }
    return entries.remove(at: index)
  }

  /// Removes and returns every entry whose time has run out.
  mutating func expire(now: Date) -> [Entry] {
    let expired = entries.filter { $0.deadline <= now }
    entries.removeAll { $0.deadline <= now }
    return expired
  }
}
