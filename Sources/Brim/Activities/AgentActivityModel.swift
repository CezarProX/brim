import AppKit
import Darwin
import SwiftUI
import UniformTypeIdentifiers

struct AgentStatus: Codable, Equatable, Sendable {
  enum State: String, Codable, Sendable { case working, waiting, completed, failed }
  let title: String
  let state: State
  let updatedAt: Date
  var model: String?
  var tokens: Int?
  var progress: Double?

  static func decode(_ data: Data, now: Date = .now) throws -> AgentStatus {
    guard data.count <= 65_536 else { throw StatusError.invalid }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let status = try decoder.decode(AgentStatus.self, from: data)
    guard !status.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      status.title.count <= 200, (status.model?.count ?? 0) <= 80,
      status.updatedAt.timeIntervalSince(now) <= 30,
      now.timeIntervalSince(status.updatedAt) <= 120,
      status.tokens.map({ $0 >= 0 }) ?? true,
      status.progress.map({ $0.isFinite && (0...1).contains($0) }) ?? true
    else { throw StatusError.invalid }
    return status
  }

  enum StatusError: LocalizedError {
    case invalid
    var errorDescription: String? { "Agent status is invalid or older than two minutes." }
  }
}

@MainActor
final class AgentActivityModel: ObservableObject {
  static let shared = AgentActivityModel()
  @Published private(set) var active: AgentStatus?
  @Published private(set) var status = "Connect a local status file from your agent or automation."
  @Published var isPresenting = false
  private var timer: Timer?
  private var reading = false
  private var generation = 0
  var isConnected: Bool { AppSettings.shared.agentStatusFile != nil }

  func start() {
    guard timer == nil, isConnected else { return }
    refresh()
    timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.refresh() }
    }
  }
  func stop() {
    timer?.invalidate()
    timer = nil
    generation += 1
  }

  func chooseFile() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.json]
    panel.canChooseDirectories = false
    isPresenting = true
    panel.begin { [weak self] response in
      MainActor.assumeIsolated {
        guard let self else { return }
        self.isPresenting = false
        guard response == .OK, let url = panel.url else { return }
        self.generation += 1
        AppSettings.shared.agentStatusFile = url.resolvingSymlinksInPath()
        self.active = nil
        self.start()
        self.refresh()
      }
    }
  }

  func disconnect() {
    stop()
    generation += 1
    AppSettings.shared.agentStatusFile = nil
    active = nil
    status = "Agent status disconnected."
  }

  func refresh() {
    guard !reading, let url = AppSettings.shared.agentStatusFile, url.isFileURL else { return }
    reading = true
    let token = generation
    Task {
      let result = await Task.detached(priority: .utility) { Result { try Self.read(url) } }.value
      reading = false
      guard token == generation else { return }
      switch result {
      case .success(let next):
        active = next
        status = "Local status connected"
      case .failure(let error):
        active = nil
        status = error.localizedDescription
      }
    }
  }

  nonisolated static func read(_ url: URL) throws -> AgentStatus {
    let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
    guard descriptor >= 0 else { throw AgentStatus.StatusError.invalid }
    defer { close(descriptor) }
    var info = stat()
    guard fstat(descriptor, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG,
      info.st_size >= 0, info.st_size <= 65_536
    else { throw AgentStatus.StatusError.invalid }
    let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
    let data = try handle.read(upToCount: 65_537) ?? Data()
    return try AgentStatus.decode(data)
  }
}

struct AgentActivityView: View {
  @ObservedObject var model: AgentActivityModel
  var body: some View {
    VStack(alignment: .leading, spacing: IslandSpace.l) {
      if let active = model.active {
        IslandHeader(
          title: active.model ?? "Agent", symbol: "terminal.fill",
          tint: IslandTint.color(for: .agent)
        ) {
          Text(active.state.rawValue.capitalized)
            .font(IslandFont.label.weight(.semibold))
            .foregroundStyle(stateColor(active.state))
            .padding(.horizontal, IslandSpace.s).frame(height: 22)
            .background(stateColor(active.state).opacity(0.16), in: Capsule())
            .contentTransition(.opacity)
        }
        Text(active.title).font(IslandFont.title.weight(.medium)).lineLimit(2)
        if let progress = active.progress {
          ProgressView(value: progress).tint(IslandTint.color(for: .agent))
        }
        if let tokens = active.tokens {
          Text("\(tokens.formatted()) tokens").font(IslandFont.label).monospacedDigit()
            .foregroundStyle(IslandInk.tertiary).contentTransition(.numericText())
        }
      } else {
        HStack(spacing: IslandSpace.l) {
          ZStack {
            Circle().fill(IslandFill.raised).frame(width: 64, height: 64)
            Image(systemName: "sparkle").font(.system(size: 24, weight: .bold))
              .foregroundStyle(Color(red: 0.85, green: 0.47, blue: 0.34)).offset(x: -9, y: -6)
            Image(systemName: "chevron.left.forwardslash.chevron.right").font(.system(size: 15, weight: .bold))
              .foregroundStyle(.teal).offset(x: 11, y: 10)
          }
          .accessibilityHidden(true)
          VStack(alignment: .leading, spacing: 3) {
            Text("No agents running").font(IslandFont.title)
            Text("Claude Code, Codex, Cursor, OpenCode and Antigravity sessions on this Mac appear here automatically while they work.")
              .font(IslandFont.body).foregroundStyle(IslandInk.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
        Text(model.isConnected ? model.status : "Other agents can report progress through a JSON status file.")
          .font(IslandFont.caption).foregroundStyle(IslandInk.tertiary)
      }
      HStack(spacing: IslandSpace.s) {
        Button(model.isConnected ? "Change status file…" : "Use a status file…", action: model.chooseFile)
          .buttonStyle(IslandPillStyle(compact: true))
        if model.isConnected {
          Button("Disconnect", action: model.disconnect).buttonStyle(IslandPillStyle(compact: true))
        }
      }
    }
  }

  private func stateColor(_ state: AgentStatus.State) -> Color {
    switch state {
    case .failed: return .red
    case .waiting: return .orange
    default: return .green
    }
  }
}
