import SwiftUI

/// Coding-agent HUD settings: which agents to follow, the plan-usage ring and its alerts, and attention flashes.
/// Self-contained; embed it in the island settings page.
struct AgentsSettingsSection: View {
  @State private var enabled: [String: Bool] = Dictionary(
    uniqueKeysWithValues: CodingAgentSession.Tool.allCases.map { ($0.settingsID, AppSettings.shared.agentEnabled($0.settingsID)) })
  @State private var ring = AppSettings.shared.agentUsageRingEnabled
  @State private var alerts = AppSettings.shared.agentUsageAlertsEnabled
  @State private var attention = AppSettings.shared.agentAttentionFlashEnabled
  @State private var answerInNotch = AppSettings.shared.agentQuestionsEnabled
  @State private var hookInstalled = ClaudeHookInstallFlow.isInstalled
  @State private var limitThousands: Int? =
    AppSettings.shared.hasClaudeTokenLimit ? AppSettings.shared.claudeTokenLimit / 1000 : nil

  var body: some View {
    Group {
      group("Agents") {
        ForEach(CodingAgentSession.Tool.allCases, id: \.settingsID) { tool in
          HStack(spacing: 10) {
            AgentMascot(tool: tool, size: 18)
            Toggle(tool.rawValue, isOn: binding(tool)).toggleStyle(.switch).controlSize(.small)
          }
        }
        Text("Everything is read from files on this Mac. Nothing is sent anywhere. Cursor sessions come from its local database, which is opened read-only.")
          .font(.footnote).foregroundStyle(.secondary)
      }
      group("Plan usage") {
        Toggle("Show a usage ring around the agent's icon", isOn: $ring)
          .onChange(of: ring) { _, value in
            AppSettings.shared.agentUsageRingEnabled = value
            if value { AgentUsageStore.shared.refresh() }
          }
        HStack {
          Text("Claude Code 5-hour limit")
          Spacer()
          TextField("", value: $limitThousands, format: .number, prompt: Text("Not set"))
            .multilineTextAlignment(.trailing).frame(width: 70).textFieldStyle(.roundedBorder)
            .onChange(of: limitThousands) { _, value in
              guard let value else { return }
              AppSettings.shared.claudeTokenLimit = max(10, value) * 1000
              AgentUsageStore.shared.refresh()
            }
          Text("thousand tokens").foregroundStyle(.secondary)
        }
        Toggle("Flash the island at 80% and 95% of the limit", isOn: $alerts)
          .onChange(of: alerts) { _, value in AppSettings.shared.agentUsageAlertsEnabled = value }
        Text("Claude Code usage is the input, output and cache-write tokens in the last 5 hours of local transcripts, measured against the limit you set; the ring stays off until you set one. Codex reports its own percentage.")
          .font(.footnote).foregroundStyle(.secondary)
      }
      group("Answer from the notch") {
        Toggle("Answer agent questions in the notch", isOn: $answerInNotch)
          .onChange(of: answerInNotch) { _, value in AgentQuestionBridge.shared.setEnabled(value) }
        Text("When Claude Code asks you a question or needs approval, the island shows it with its choices and a reply field. Your answer goes back over a private socket on this Mac; nothing is sent anywhere.")
          .font(.footnote).foregroundStyle(.secondary)
        HStack {
          Button("Install Claude Code hook…") { hookInstalled = ClaudeHookInstallFlow.run() || ClaudeHookInstallFlow.isInstalled }
          if hookInstalled {
            Button("Remove hook") { _ = ClaudeHookInstallFlow.remove(); hookInstalled = ClaudeHookInstallFlow.isInstalled }
            Text("Installed").font(.footnote).foregroundStyle(.secondary)
          }
        }
        Text("You see exactly what will be added to ~/.claude/settings.json before anything is written. If Brim is not running, Claude Code asks in its terminal as usual.")
          .font(.footnote).foregroundStyle(.secondary)
      }
      group("Attention") {
        Toggle("Flash the island when an agent needs your approval or an answer", isOn: $attention)
          .onChange(of: attention) { _, value in AppSettings.shared.agentAttentionFlashEnabled = value }
        Text("Tap the agent in the island to jump to the app it runs in.").font(.footnote).foregroundStyle(.secondary)
      }
    }
  }

  private func binding(_ tool: CodingAgentSession.Tool) -> Binding<Bool> {
    Binding(
      get: { enabled[tool.settingsID] ?? true },
      set: { value in
        enabled[tool.settingsID] = value
        AppSettings.shared.setAgentEnabled(tool.settingsID, value)
        AgentUsageStore.shared.refresh()
      })
  }

  private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
    SettingsSection(title) { content() }
  }
}
