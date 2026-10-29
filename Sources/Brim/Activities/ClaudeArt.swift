import AppKit
import SwiftUI

/// Claude Code's own artwork (Clawd), read from the Claude Code editor extension already installed on
/// this Mac rather than bundled into Brim. Without the extension the notch falls back to an SF Symbol.
enum ClaudeArt {
  static let extensionRoots: [URL] = [".antigravity-ide/extensions", ".vscode/extensions", ".cursor/extensions",
                                      ".windsurf/extensions"].map {
    FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent($0, isDirectory: true)
  }

  static let clawd: NSImage? = resource(named: "clawd.svg", in: extensionRoots).flatMap(NSImage.init(contentsOf:))

  /// The file from the newest `anthropic.claude-code-<version>` extension in any of `roots`.
  static func resource(named name: String, in roots: [URL]) -> URL? {
    let candidates = roots.flatMap { root in
      ((try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [])
        .filter { $0.lastPathComponent.hasPrefix("anthropic.claude-code-") }
    }
    let newestFirst = candidates.sorted {
      $0.lastPathComponent.compare($1.lastPathComponent, options: .numeric) == .orderedDescending
    }
    return newestFirst.lazy
      .map { $0.appendingPathComponent("resources").appendingPathComponent(name) }
      .first { FileManager.default.isReadableFile(atPath: $0.path) }
  }
}

/// The agent's mark for the compact wing: Clawd for Claude Code when available, otherwise a vector mascot,
/// wrapped in the plan-usage ring and a pulse while the agent waits for the user.
struct AgentGlyph: View {
  let tool: CodingAgentSession.Tool
  var size: CGFloat = 20
  /// Previews and tests pin these; the live notch reads them from the shared stores.
  var usageFraction: Double?
  var attention: Bool?
  var vectorOnly = false
  @ObservedObject private var coding = CodingAgentModel.shared
  @ObservedObject private var usage = AgentUsageStore.shared

  private var ringFraction: Double? { usageFraction ?? usage.reading(for: tool)?.fraction }
  private var needsAttention: Bool {
    attention ?? (coding.session.map { $0.tool == tool && $0.needsAttention } ?? false)
  }

  var body: some View {
    ZStack {
      if let fraction = ringFraction {
        AgentUsageRing(fraction: fraction, tint: AgentBrand.color(tool), lineWidth: max(1.5, size * 0.09))
      }
      if needsAttention { AgentAttentionPulse(color: .orange).frame(width: size + 6, height: size + 6) }
      mark
    }
    .frame(width: size, height: size)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(needsAttention ? "\(tool.rawValue) needs you" : tool.rawValue)
  }

  private var markSize: CGFloat { size * (ringFraction == nil ? 1 : 0.7) }

  @ViewBuilder
  private var mark: some View {
    if tool == .claude, !vectorOnly, let clawd = ClaudeArt.clawd {
      Image(nsImage: clawd).resizable().aspectRatio(contentMode: .fit).frame(width: markSize, height: markSize)
    } else {
      AgentMascot(tool: tool, size: markSize)
    }
  }
}
