import Foundation
import Testing

@testable import Brim

struct AgentStatusTests {
  private func payload(now: Date, progress: Double = 0.5) throws -> Data {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return try encoder.encode(
      AgentStatus(
        title: "Fixture build", state: .working, updatedAt: now,
        model: "Fixture model", tokens: 100, progress: progress))
  }

  @Test func validStatusPreservesReportedValues() throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let status = try AgentStatus.decode(payload(now: now), now: now)
    #expect(status.tokens == 100)
    #expect(status.progress == 0.5)
    #expect(status.state == .working)
  }

  @Test func staleFutureOversizedAndInvalidProgressAreRejected() throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    #expect(throws: (any Error).self) {
      try AgentStatus.decode(payload(now: now.addingTimeInterval(-121)), now: now)
    }
    #expect(throws: (any Error).self) {
      try AgentStatus.decode(payload(now: now.addingTimeInterval(60)), now: now)
    }
    #expect(throws: (any Error).self) {
      try AgentStatus.decode(payload(now: now, progress: 1.2), now: now)
    }
    #expect(throws: (any Error).self) {
      try AgentStatus.decode(Data(repeating: 32, count: 65_537), now: now)
    }
  }

  @Test func pollingRejectsSymlinksAndDirectories() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("state.json")
    try payload(now: .now).write(to: file)
    let symlink = directory.appendingPathComponent("link.json")
    try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: file)
    #expect(try AgentActivityModel.read(file).state == .working)
    #expect(throws: (any Error).self) { try AgentActivityModel.read(symlink) }
    #expect(throws: (any Error).self) { try AgentActivityModel.read(directory) }
  }
}
