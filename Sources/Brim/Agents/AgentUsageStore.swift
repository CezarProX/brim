import Foundation
import SwiftUI

/// Plan-usage rings: Claude Code from the local 5-hour token window, Codex from the `rate_limits` it logs.
@MainActor
final class AgentUsageStore: ObservableObject {
  static let shared = AgentUsageStore()
  @Published private(set) var claude: UsageReading?
  @Published private(set) var codex: UsageReading?
  private var alerted: [CodingAgentSession.Tool: Set<Double>] = [:]
  private var timer: Timer?
  private var reading = false
  private let queue = DispatchQueue(label: "Brim.AgentUsage", qos: .utility)
  private let cache = SampleCache()

  func start() {
    guard timer == nil else { return }
    refresh()
    timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.refresh() }
    }
  }

  func stop() {
    timer?.invalidate()
    timer = nil
    claude = nil
    codex = nil
  }

  func reading(for tool: CodingAgentSession.Tool) -> UsageReading? {
    guard AppSettings.shared.agentUsageRingEnabled else { return nil }
    switch tool {
    case .claude: return claude
    case .codex: return codex
    default: return nil
    }
  }

  func refresh() {
    guard !reading else { return }
    reading = true
    let settings = AppSettings.shared
    let limit = settings.claudeTokenLimit
    let hasLimit = settings.hasClaudeTokenLimit
    let wantClaude = settings.agentEnabled("claude")
    let wantCodex = settings.agentEnabled("codex")
    let cache = cache
    queue.async { [weak self] in
      let home = FileManager.default.homeDirectoryForCurrentUser
      let now = Date()
      let claude = wantClaude && hasLimit ? AgentUsageMath.reading(cache.claudeSamples(home: home, now: now), limit: limit, now: now) : nil
      let codex = wantCodex ? Self.codexReading(home: home, now: now) : nil
      Task { @MainActor in
        guard let self else { return }
        self.reading = false
        if self.claude != claude { self.claude = claude }
        if self.codex != codex { self.codex = codex }
        self.raiseAlerts()
      }
    }
  }

  private func raiseAlerts() {
    guard AppSettings.shared.agentUsageAlertsEnabled else { return }
    for (tool, reading) in [(CodingAgentSession.Tool.claude, claude), (.codex, codex)] {
      guard let reading else { alerted[tool] = []; continue }
      let outcome = UsageAlertPolicy.evaluate(fraction: reading.fraction, alerted: alerted[tool] ?? [])
      alerted[tool] = outcome.alerted
      guard let level = outcome.fire else { continue }
      let critical = level >= 0.95
      IslandFlashCenter.shared.show(
        "\(tool.rawValue) \(reading.percent)% used", symbol: critical ? "exclamationmark.triangle.fill" : "gauge.with.dots.needle.67percent",
        tint: critical ? .red : .orange, value: reading.fraction, duration: 4)
    }
  }

  nonisolated private static func codexReading(home: URL, now: Date) -> UsageReading? {
    let files = SampleCache.recent(in: home.appendingPathComponent(".codex/sessions"), within: AgentUsageMath.windowLength, now: now)
    guard let newest = files.max(by: { $0.modified < $1.modified }) else { return nil }
    let reading = AgentUsageMath.codexReading(lines: CodingAgentModel.tail(of: newest.url, bytes: 256 * 1024))
    // A window that already reset reports a stale percentage.
    if let reset = reading?.resetsAt, reset < now { return nil }
    return reading
  }

  /// Parsed samples per transcript, reused until the file changes. Only touched on the usage queue.
  final class SampleCache: @unchecked Sendable {
    private var entries: [String: (modified: Date, samples: [UsageSample])] = [:]

    struct File { let url: URL; let modified: Date }

    func claudeSamples(home: URL, now: Date) -> [UsageSample] {
      let files = Self.recent(in: home.appendingPathComponent(".claude/projects"), within: AgentUsageMath.windowLength, now: now)
      let paths = Set(files.map(\.url.path))
      entries = entries.filter { paths.contains($0.key) }
      return files.flatMap { file -> [UsageSample] in
        if let cached = entries[file.url.path], cached.modified == file.modified { return cached.samples }
        let samples = Self.samples(in: file.url)
        entries[file.url.path] = (file.modified, samples)
        return samples
      }
    }

    static func samples(in url: URL) -> [UsageSample] {
      guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return [] }
      let marker = Data("\"usage\"".utf8)
      return data.split(separator: UInt8(ascii: "\n")).compactMap { line in
        let slice = Data(line)
        return slice.range(of: marker) == nil ? nil : AgentUsageMath.sample(line: slice)
      }
    }

    static func recent(in root: URL, within seconds: TimeInterval, now: Date) -> [File] {
      guard
        let enumerator = FileManager.default.enumerator(
          at: root, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])
      else { return [] }
      var files: [File] = []
      for case let url as URL in enumerator where url.pathExtension == "jsonl" {
        if let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
          now.timeIntervalSince(modified) < seconds
        {
          files.append(File(url: url, modified: modified))
        }
      }
      return files
    }
  }
}
