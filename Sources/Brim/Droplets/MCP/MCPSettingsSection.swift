import AppKit
import SwiftUI

/// MCP settings: master switch, one consent switch per tool (all off by default), setup text.
struct MCPSettingsSection: View {
  @State private var enabled = AppSettings.shared.mcpEnabled
  @State private var allowed = AppSettings.shared.mcpAllowedTools
  @State private var copied = false

  var body: some View {
    SettingsSection("MCP") {
      Toggle("Let AI apps use Brim through MCP", isOn: $enabled)
        .onChange(of: enabled) { _, value in
          AppSettings.shared.mcpEnabled = value
          value ? MCPSocketServer.shared.start() : MCPSocketServer.shared.stop()
        }
      Text("Nothing is shared until you switch a tool on. Every call, allowed or refused, flashes in the island. Everything stays on this Mac.")
        .font(.footnote).foregroundStyle(.secondary)
      if enabled {
        ForEach(MCPCatalog.tools, id: \.name) { tool in
          Toggle(isOn: binding(tool.name)) {
            VStack(alignment: .leading, spacing: 1) {
              Text(tool.title)
              Text(tool.detail).font(.footnote).foregroundStyle(.secondary)
            }
          }
        }
        setup
      }
    }
  }

  private var setup: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Connect an app").font(.subheadline.weight(.semibold))
      ScrollView {
        Text(MCPSetupText.instructions(executable: MCPSetupText.executable))
          .font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading).padding(8)
      }
      .frame(height: 170).background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
      Button(copied ? "Copied" : "Copy instructions") {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(MCPSetupText.instructions(executable: MCPSetupText.executable), forType: .string)
        copied = true
      }
    }
  }

  private func binding(_ name: String) -> Binding<Bool> {
    Binding(
      get: { allowed.contains(name) },
      set: { on in
        if on { allowed.insert(name) } else { allowed.remove(name) }
        AppSettings.shared.mcpAllowedTools = allowed
      })
  }
}
