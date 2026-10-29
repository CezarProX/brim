// AgentsHubView.swift
// Brim
//
// The Agents app: live coding-agent sessions, plan usage, and the switch for answering their
// questions from the island. Everything it needs is set up here, not in Settings.

import AppKit
import SwiftUI

// MARK: - Detection

/// Which agents leave their files on this Mac, so the hub can say what it will see.
enum AgentDetection {
  static func isInstalled(_ tool: CodingAgentSession.Tool, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Bool {
    let files = FileManager.default
    func exists(_ relative: String) -> Bool { files.fileExists(atPath: home.appendingPathComponent(relative).path) }
    switch tool {
    case .claude: return exists(".claude/projects")
    case .codex: return exists(".codex/sessions")
    case .cursor: return files.fileExists(atPath: CursorSessionReader.databaseURL(home: home).path)
    case .openCode: return files.fileExists(atPath: OpenCodeSessionReader.defaultRoot(home: home).path)
    case .antigravity: return AntigravitySessionReader.brainFolders(home: home).contains { files.fileExists(atPath: $0.path) }
    }
  }

  /// "Found: Claude Code, Codex" or a pointer when nothing was found.
  static func summary(followed: [CodingAgentSession.Tool], installed: Set<CodingAgentSession.Tool>) -> String {
    let active = followed.filter(installed.contains)
    guard !active.isEmpty else {
      return installed.isEmpty
        ? L10n.tr("No coding agents found on this Mac yet.")
        : L10n.tr("Found agents are switched off. Tap one to follow it.")
    }
    return L10n.tr("Following: %@", active.map(\.rawValue).joined(separator: ", "))
  }
}

// MARK: - Answering setup

/// The "Answer agent questions" switch and the Claude Code hook behind it, usable inline.
@MainActor
final class AgentAnswerSetup: ObservableObject {
  @Published private(set) var enabled: Bool
  @Published private(set) var hookInstalled: Bool

  init() {
    enabled = AppSettings.shared.agentQuestionsEnabled
    hookInstalled = ClaudeHookInstallFlow.isInstalled
  }

  func setEnabled(_ value: Bool) {
    AgentQuestionBridge.shared.setEnabled(value)
    enabled = AppSettings.shared.agentQuestionsEnabled
    hookInstalled = ClaudeHookInstallFlow.isInstalled
  }

  /// Shows the confirm-then-write dialog; nothing is written until the user presses Install there.
  func installHook() {
    // The dialog is app-modal: open it after this click has finished and the island has closed,
    // so the island's panel and its click handling can't sit under (or swallow clicks for) it.
    NotchShelfController.shared.dismissShelf()
    DispatchQueue.main.async { [weak self] in
      _ = ClaudeHookInstallFlow.run()
      self?.hookInstalled = ClaudeHookInstallFlow.isInstalled
    }
  }

  enum Phase: Equatable { case off, needsHook, ready }
  var phase: Phase { !enabled ? .off : (hookInstalled ? .ready : .needsHook) }
}

// MARK: - Hub

struct AgentsHubView: View {
  @ObservedObject var coding: CodingAgentModel
  @ObservedObject var status: AgentActivityModel
  @ObservedObject var usage: AgentUsageStore
  @StateObject private var setup = AgentAnswerSetup()

  @MainActor init(coding: CodingAgentModel, status: AgentActivityModel, usage: AgentUsageStore? = nil) {
    self.coding = coding
    self.status = status
    self.usage = usage ?? .shared
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if let session = coding.session, session.isLive() {
        CodingAgentView(
          session: session, sessions: coding.sessions, pinnedID: coding.pinnedID,
          onSelect: coding.select, usage: usage.reading(for: session.tool)
        ) {
          AnswerIconButton(setup: setup)
        }
      } else if status.active != nil {
        AgentActivityView(model: status)
        AgentsStrip(usage: usage, setup: setup)
      } else {
        AgentsIdleView(status: status, usage: usage, setup: setup)
      }
    }
    .frame(maxWidth: .infinity, alignment: .topLeading)
    .background { GeometryReader { Color.clear.preference(key: AgentsHubHeightKey.self, value: $0.size.height) } }
    .contentShape(Rectangle())
    .contextMenu {
      Button(answerMenuTitle) {
        setup.phase == .needsHook ? setup.installHook() : setup.setEnabled(setup.phase == .off)
      }
      Button("Agents Settings…") { AgentsHubLinks.openSettings() }
    }
    .onAppear { usage.refresh() }
  }

  private var answerMenuTitle: String {
    switch setup.phase {
    case .off: L10n.tr("Answer questions")
    case .needsHook: L10n.tr("Install hook…")
    case .ready: L10n.tr("Stop answering questions")
    }
  }
}

/// The answer switch as one quiet icon for the live session's bottom row: green when on.
struct AnswerIconButton: View {
  @ObservedObject var setup: AgentAnswerSetup
  @State private var hovered = false

  var body: some View {
    Button {
      switch setup.phase {
      case .off: setup.setEnabled(true)
      case .needsHook: setup.installHook()
      case .ready: setup.setEnabled(false)
      }
    } label: {
      Image(systemName: icon).font(.system(size: 11, weight: .semibold))
        .foregroundStyle(tint)
        .frame(width: 24, height: 24)
        .background(setup.phase == .ready ? Color.green.opacity(0.16) : (hovered ? IslandFill.hover : IslandFill.subtle), in: Circle())
        .contentTransition(.symbolEffect(.replace))
    }
    .buttonStyle(IslandPressStyle(pressedScale: 0.88))
    .onHover { hovered = $0 }
    .help(help)
    .accessibilityLabel(L10n.tr("Answer questions"))
    .accessibilityValue(setup.phase == .ready ? L10n.tr("On") : L10n.tr("Off"))
  }

  private var icon: String {
    switch setup.phase {
    case .off: "bubble.left"
    case .needsHook: "arrow.down.circle"
    case .ready: "bubble.left.fill"
    }
  }

  private var tint: Color {
    switch setup.phase {
    case .off: hovered ? IslandInk.primary : IslandInk.secondary
    case .needsHook: .orange
    case .ready: .green
    }
  }

  private var help: String {
    switch setup.phase {
    case .off: L10n.tr("Reply to Claude Code's questions and approvals from the island")
    case .needsHook: L10n.tr("Add the Brim hook to Claude Code. You see exactly what changes first.")
    case .ready: L10n.tr("Claude Code's questions appear in the island. Click to turn off.")
    }
  }
}

/// The hub's natural height, so the island can hug it instead of leaving an empty band under it.
struct AgentsHubHeightKey: PreferenceKey {
  static let defaultValue: CGFloat? = nil
  static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) { value = nextValue() ?? value }

  /// The page height for a hub of `content` points: the measured hub plus the host's own chrome,
  /// never taller than the page it used to have, and never jumping for a pixel or two.
  static func pageHeight(content: CGFloat?, chrome: CGFloat, cap: CGFloat) -> CGFloat {
    guard let content, content > 0 else { return cap }
    return min(cap, (chrome + content).rounded(.up))
  }
}

// MARK: - Live strip

/// One slim row under a live session: usage rings on the left, answer switch and settings on the right.
struct AgentsStrip: View {
  @ObservedObject var usage: AgentUsageStore
  @ObservedObject var setup: AgentAnswerSetup

  var body: some View {
    HStack(spacing: IslandSpace.m) {
      UsageRings(usage: usage, showsEmpty: false)
      Spacer(minLength: 0)
      AnswerChip(setup: setup)
      SettingsGear()
    }
    .frame(minHeight: 28)
  }
}

private struct SettingsGear: View {
  var body: some View {
    DropletIconButton(symbol: "gearshape", help: "Open Agents settings", size: 28) {
      AgentsHubLinks.openSettings()
    }
  }
}

/// Where the hub sends people for the full settings page.
@MainActor
enum AgentsHubLinks {
  /// Opens Settings on Home & Widgets > Agents & Meetings.
  static func openSettings() { SettingsWindowController.shared.show(.tool(.agents)) }
}

/// "Answers on" / "Answer questions" pill that flips the switch, or finishes setup when the hook is missing.
struct AnswerChip: View {
  @ObservedObject var setup: AgentAnswerSetup

  var body: some View {
    Button {
      switch setup.phase {
      case .off: setup.setEnabled(true)
      case .needsHook: setup.installHook()
      case .ready: setup.setEnabled(false)
      }
    } label: {
      HStack(spacing: 6) {
        Image(systemName: icon).font(.system(size: 12, weight: .semibold))
        Text(title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
      }
      .foregroundStyle(setup.phase == .ready ? Color.green : IslandInk.primary)
      .padding(.horizontal, 12).frame(height: 28)
      .background((setup.phase == .ready ? Color.green.opacity(0.16) : IslandFill.raised), in: Capsule())
      .contentShape(Capsule())
    }
    .buttonStyle(IslandPressStyle(pressedScale: 0.95))
    .help(help)
    .accessibilityLabel(title)
  }

  private var icon: String {
    switch setup.phase {
    case .off: "bubble.left.and.text.bubble.right"
    case .needsHook: "arrow.down.circle"
    case .ready: "checkmark.bubble.fill"
    }
  }

  private var title: String {
    switch setup.phase {
    case .off: L10n.tr("Answer questions")
    case .needsHook: L10n.tr("Install hook…")
    case .ready: L10n.tr("Answers on")
    }
  }

  private var help: String {
    switch setup.phase {
    case .off: L10n.tr("Reply to Claude Code's questions and approvals from the island")
    case .needsHook: L10n.tr("Add the Brim hook to Claude Code. You see exactly what changes first.")
    case .ready: L10n.tr("Claude Code's questions appear in the island. Click to turn off.")
    }
  }
}

// MARK: - Usage

/// Plan-usage rings: Claude Code (against a limit you set) and Codex (it reports its own percentage).
struct UsageRings: View {
  @ObservedObject var usage: AgentUsageStore
  /// Also draw a placeholder for an agent with no reading.
  var showsEmpty = true
  @State private var editingLimit = false

  var body: some View {
    HStack(spacing: IslandSpace.m) {
      ring(.claude, reading: usage.reading(for: .claude))
      ring(.codex, reading: usage.reading(for: .codex))
    }
  }

  @ViewBuilder private func ring(_ tool: CodingAgentSession.Tool, reading: UsageReading?) -> some View {
    if let reading {
      HStack(spacing: 6) {
        AgentUsageRing(fraction: reading.fraction, tint: AgentBrand.color(tool), lineWidth: 3).frame(width: 20, height: 20)
        VStack(alignment: .leading, spacing: 0) {
          Text("\(tool.rawValue) \(reading.percent)%").font(.system(size: 12, weight: .semibold)).monospacedDigit()
            .foregroundStyle(IslandInk.primary)
          if let reset = reading.resetsAt {
            Text(L10n.tr("resets %@", reset.formatted(date: .omitted, time: .shortened)))
              .font(.system(size: 12)).foregroundStyle(IslandInk.tertiary)
          }
        }
      }
      .help(L10n.tr("Share of the 5-hour plan window used"))
    } else if showsEmpty {
      emptyRing(tool)
    }
  }

  @ViewBuilder private func emptyRing(_ tool: CodingAgentSession.Tool) -> some View {
    HStack(spacing: 6) {
      AgentUsageRing(fraction: 0, tint: AgentBrand.color(tool), lineWidth: 3).frame(width: 20, height: 20).opacity(0.5)
      if tool == .claude, AppSettings.shared.agentEnabled("claude"), !AppSettings.shared.hasClaudeTokenLimit {
        Button { editingLimit = true } label: {
          Text("Set Claude limit").font(.system(size: 12, weight: .semibold)).foregroundStyle(IslandInk.primary)
            .padding(.horizontal, 10).frame(height: 28).background(IslandFill.raised, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $editingLimit, arrowEdge: .bottom) { ClaudeLimitEditor(usage: usage) { editingLimit = false } }
        .help("Tell Brim how many tokens your 5-hour Claude Code window allows")
      } else {
        Text(tool == .claude ? L10n.tr("Claude Code idle") : L10n.tr("Codex idle"))
          .font(.system(size: 12)).foregroundStyle(IslandInk.tertiary)
      }
    }
  }
}

/// Inline version of the Settings field: the 5-hour Claude Code limit in thousands of tokens.
private struct ClaudeLimitEditor: View {
  @ObservedObject var usage: AgentUsageStore
  let done: () -> Void
  @State private var thousands = AppSettings.shared.claudeTokenLimit / 1000

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Claude Code 5-hour limit").font(.headline)
      HStack {
        TextField("", value: $thousands, format: .number).textFieldStyle(.roundedBorder).frame(width: 90)
        Text("thousand tokens").foregroundStyle(.secondary)
      }
      Text("Anthropic doesn't publish plan limits locally, so set the one that matches your plan. The ring measures the last 5 hours of local transcripts against it.")
        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      HStack {
        Spacer()
        Button("Set limit") {
          AppSettings.shared.claudeTokenLimit = max(10, thousands) * 1000
          usage.refresh()
          done()
        }
        .keyboardShortcut(.defaultAction)
      }
    }
    .padding(12).frame(width: 300)
  }
}

// MARK: - Nothing live

/// First-run and between-sessions state: what it follows, usage, and the answer switch.
struct AgentsIdleView: View {
  @ObservedObject var status: AgentActivityModel
  @ObservedObject var usage: AgentUsageStore
  @ObservedObject var setup: AgentAnswerSetup
  @State private var enabled: [CodingAgentSession.Tool: Bool] = Dictionary(
    uniqueKeysWithValues: CodingAgentSession.Tool.allCases.map { ($0, AppSettings.shared.agentEnabled($0.settingsID)) })
  private let installed = Set(CodingAgentSession.Tool.allCases.filter { AgentDetection.isInstalled($0) })

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 6) {
        ForEach(CodingAgentSession.Tool.allCases, id: \.self) { tool in chip(tool) }
      }
      Text(AgentDetection.summary(followed: CodingAgentSession.Tool.allCases.filter { enabled[$0] ?? true }, installed: installed))
        .font(.system(size: 12)).foregroundStyle(IslandInk.secondary).lineLimit(1)
      HStack(spacing: IslandSpace.l) {
        UsageRings(usage: usage)
        Spacer(minLength: 0)
      }
      .padding(.horizontal, IslandSpace.m).frame(minHeight: 40)
      .glassCard(radius: IslandRadius.medium)
      answerCard
      footer
    }
  }

  private func chip(_ tool: CodingAgentSession.Tool) -> some View {
    let on = enabled[tool] ?? true
    let found = installed.contains(tool)
    return Button {
      enabled[tool] = !on
      AppSettings.shared.setAgentEnabled(tool.settingsID, !on)
      AgentUsageStore.shared.refresh()
    } label: {
      VStack(spacing: 3) {
        AgentMascot(tool: tool, size: 22)
        Text(tool.rawValue).font(.system(size: 12, weight: .medium)).lineLimit(1).minimumScaleFactor(0.8)
          .foregroundStyle(on ? IslandInk.primary : IslandInk.tertiary)
      }
      .frame(maxWidth: .infinity, minHeight: 52)
      .background(on ? IslandFill.raised : IslandFill.subtle, in: RoundedRectangle(cornerRadius: IslandRadius.small, style: .continuous))
      .overlay(alignment: .topTrailing) {
        Circle().fill(on && found ? Color.green : IslandInk.tertiary).frame(width: 7, height: 7).padding(6)
      }
      .opacity(found || on ? 1 : 0.55)
      .contentShape(RoundedRectangle(cornerRadius: IslandRadius.small, style: .continuous))
    }
    .buttonStyle(IslandPressStyle(pressedScale: 0.95))
    .help(on ? L10n.tr("Following %@. Click to stop.", tool.rawValue) : L10n.tr("Not following %@. Click to follow.", tool.rawValue))
    .accessibilityLabel(tool.rawValue)
    .accessibilityValue(on ? L10n.tr("On") : L10n.tr("Off"))
  }

  private var answerCard: some View {
    HStack(spacing: IslandSpace.m) {
      Image(systemName: "bubble.left.and.text.bubble.right.fill").font(.system(size: 14, weight: .semibold))
        .foregroundStyle(setup.phase == .ready ? Color.green : Color.orange)
        .frame(width: 32, height: 32)
        .background((setup.phase == .ready ? Color.green : Color.orange).opacity(0.16), in: Circle())
      VStack(alignment: .leading, spacing: 1) {
        Text("Answer agent questions").font(IslandFont.headline).foregroundStyle(IslandInk.primary)
        Text(answerDetail).font(.system(size: 12)).foregroundStyle(IslandInk.secondary).lineLimit(2)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: IslandSpace.s)
      AnswerChip(setup: setup)
    }
    .padding(.horizontal, IslandSpace.m).padding(.vertical, 6).frame(minHeight: 48)
    .glassCard(radius: IslandRadius.medium)
  }

  private var answerDetail: String {
    switch setup.phase {
    case .off: L10n.tr("When Claude Code asks or needs approval, reply right here.")
    case .needsHook: L10n.tr("On. One more step: add the hook to Claude Code.")
    case .ready: L10n.tr("On. Claude Code's questions will appear in the island.")
    }
  }

  private var footer: some View {
    HStack(spacing: IslandSpace.s) {
      Text(status.isConnected ? status.status : L10n.tr("Waiting for a session. Start one in your agent and it shows up here."))
        .font(.system(size: 12)).foregroundStyle(IslandInk.tertiary).lineLimit(1)
      Spacer(minLength: 0)
      Button(status.isConnected ? L10n.tr("Change status file…") : L10n.tr("Use a status file…"), action: status.chooseFile)
        .buttonStyle(.plain).font(.system(size: 12, weight: .medium)).foregroundStyle(IslandInk.secondary)
        .frame(minHeight: 28)
        .help("For tools Brim can't read: they write a small JSON file, and Brim shows it")
      SettingsGear()
    }
  }
}
