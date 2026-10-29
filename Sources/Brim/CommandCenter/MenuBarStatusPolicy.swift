import Foundation

/// What the menu-bar icon should look like right now. Pure, so every priority rule is testable.
enum MenuBarStatusPolicy {
  enum Icon: Equatable {
    case idle, music, timer, recording, agent, agentNeedsInput

    var symbol: String {
      switch self {
      case .idle: "camera.viewfinder"
      case .music: "waveform"
      case .timer: "timer"
      case .recording: "record.circle.fill"
      case .agent: "sparkles"
      case .agentNeedsInput: "exclamationmark.bubble.fill"
      }
    }

    /// Recording is the one state that must not look like a plain template icon.
    var isAlert: Bool { self == .recording || self == .agentNeedsInput }
  }

  struct Input: Equatable {
    var liveStatus = true
    var isRecording = false
    /// Seconds left on a running or paused timer; nil when none.
    var timerRemaining: TimeInterval?
    var timerPaused = false
    var agentRunning = false
    var agentNeedsInput = false
    var musicPlaying = false
    var songText: String?
    var showsSong = false
    /// The floating player's own menu-bar item already shows the song.
    var playerItemShowsSong = false
    var statsReadout: String?
  }

  struct Output: Equatable {
    var icon: Icon
    var title: String
  }

  /// recording > agent waiting on you > timer > agent working > music > idle.
  static func output(_ input: Input) -> Output {
    let icon = input.liveStatus ? chooseIcon(input) : .idle
    var parts: [String] = []
    if input.liveStatus, icon == .timer, let remaining = input.timerRemaining {
      parts.append((input.timerPaused ? "‖ " : "") + clock(remaining))
    }
    if input.showsSong, !input.playerItemShowsSong, input.musicPlaying, icon != .timer,
      let song = input.songText, !song.isEmpty {
      parts.append(song)
    }
    if let readout = input.statsReadout, !readout.isEmpty { parts.append(readout) }
    return Output(icon: icon, title: parts.joined(separator: " · "))
  }

  private static func chooseIcon(_ input: Input) -> Icon {
    if input.isRecording { return .recording }
    if input.agentNeedsInput { return .agentNeedsInput }
    if input.timerRemaining != nil { return .timer }
    if input.agentRunning { return .agent }
    if input.musicPlaying { return .music }
    return .idle
  }

  /// 65 -> "1:05", 3725 -> "1:02:05".
  static func clock(_ seconds: TimeInterval) -> String {
    let total = max(0, Int(seconds.rounded(.up)))
    let h = total / 3600, m = (total % 3600) / 60, s = total % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
  }

  /// The compact number shown beside the icon for the chosen stat.
  static func readout(_ kind: MenuBarStatsReadout, cpu: Double, memory: Double, down: Double, up: Double,
                      battery: Int?, charging: Bool) -> String? {
    func pct(_ v: Double) -> String { "\(Int((min(1, max(0, v)) * 100).rounded()))%" }
    switch kind {
    case .off: return nil
    case .cpu: return "CPU " + pct(cpu)
    case .memory: return "RAM " + pct(memory)
    case .network:
      let short = { (v: Double) in NetworkMath.format(v).replacingOccurrences(of: "/s", with: "") }
      return "↓" + short(down) + " ↑" + short(up)
    case .battery: return battery.map { "\($0)%" + (charging ? "⚡︎" : "") }
    }
  }
}
