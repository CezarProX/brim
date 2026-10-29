import AppKit
import SwiftUI

/// Brand color, app and mascot per agent.
enum AgentBrand {
  static func color(_ tool: CodingAgentSession.Tool) -> Color {
    switch tool {
    case .claude: Color(red: 0.85, green: 0.47, blue: 0.34)
    case .codex: Color(red: 0.30, green: 0.80, blue: 0.72)
    case .cursor: Color(red: 0.56, green: 0.62, blue: 1.0)
    case .openCode: Color(red: 0.62, green: 0.88, blue: 0.40)
    case .antigravity: Color(red: 0.42, green: 0.60, blue: 1.0)
    }
  }

  /// Bundle identifiers to bring forward when the user taps a session, most specific first.
  static func bundleIDs(_ tool: CodingAgentSession.Tool) -> [String] {
    switch tool {
    case .claude: ["com.anthropic.claudefordesktop"]
    case .codex: ["com.openai.codex"]
    case .cursor: ["com.todesktop.230313mzl4w4u92"]
    case .openCode: ["ai.opencode.desktop", "com.anomaly.opencode"]
    case .antigravity: ["com.google.antigravity"]
    }
  }

  /// Terminals tried when an agent that normally lives in a terminal has no owning app of its own.
  static let terminalBundleIDs = [
    "com.mitchellh.ghostty", "com.googlecode.iterm2", "dev.warp.Warp-Stable", "com.apple.Terminal",
  ]
}

/// A small vector mascot per agent, drawn from simple shapes (no bundled artwork).
struct AgentMascot: View {
  let tool: CodingAgentSession.Tool
  var size: CGFloat = 20

  var body: some View {
    Canvas { context, canvas in
      let rect = CGRect(origin: .zero, size: canvas)
      let color = AgentBrand.color(tool)
      switch tool {
      case .claude: Self.spark(&context, rect, color)
      case .codex: Self.prompt(&context, rect, color)
      case .cursor: Self.pointer(&context, rect, color)
      case .openCode: Self.brackets(&context, rect, color)
      case .antigravity: Self.peak(&context, rect, color)
      }
    }
    .frame(width: size, height: size)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(tool.rawValue)
  }

  /// Rounded rays around a center: a spark.
  private static func spark(_ context: inout GraphicsContext, _ rect: CGRect, _ color: Color) {
    let center = CGPoint(x: rect.midX, y: rect.midY)
    for index in 0..<8 {
      let angle = Double(index) * .pi / 4
      let long = index.isMultiple(of: 2)
      let inner = rect.width * 0.10, outer = rect.width * (long ? 0.46 : 0.36)
      var ray = Path()
      ray.move(to: CGPoint(x: center.x + cos(angle) * inner, y: center.y + sin(angle) * inner))
      ray.addLine(to: CGPoint(x: center.x + cos(angle) * outer, y: center.y + sin(angle) * outer))
      context.stroke(ray, with: .color(color), style: StrokeStyle(lineWidth: rect.width * 0.13, lineCap: .round))
    }
  }

  /// A rounded terminal tile with a `>_` prompt.
  private static func prompt(_ context: inout GraphicsContext, _ rect: CGRect, _ color: Color) {
    let tile = rect.insetBy(dx: rect.width * 0.06, dy: rect.height * 0.14)
    context.fill(Path(roundedRect: tile, cornerRadius: rect.width * 0.28, style: .continuous), with: .color(color))
    var chevron = Path()
    chevron.move(to: CGPoint(x: rect.width * 0.30, y: rect.height * 0.36))
    chevron.addLine(to: CGPoint(x: rect.width * 0.46, y: rect.height * 0.50))
    chevron.addLine(to: CGPoint(x: rect.width * 0.30, y: rect.height * 0.64))
    let ink = Color.black.opacity(0.78)
    context.stroke(chevron, with: .color(ink), style: StrokeStyle(lineWidth: rect.width * 0.11, lineCap: .round, lineJoin: .round))
    var underscore = Path()
    underscore.move(to: CGPoint(x: rect.width * 0.54, y: rect.height * 0.66))
    underscore.addLine(to: CGPoint(x: rect.width * 0.70, y: rect.height * 0.66))
    context.stroke(underscore, with: .color(ink), style: StrokeStyle(lineWidth: rect.width * 0.11, lineCap: .round))
  }

  /// A pointer arrow in a soft rounded square.
  private static func pointer(_ context: inout GraphicsContext, _ rect: CGRect, _ color: Color) {
    let tile = rect.insetBy(dx: rect.width * 0.06, dy: rect.height * 0.06)
    context.fill(Path(roundedRect: tile, cornerRadius: rect.width * 0.26, style: .continuous), with: .color(color.opacity(0.28)))
    var arrow = Path()
    arrow.move(to: CGPoint(x: rect.width * 0.30, y: rect.height * 0.24))
    arrow.addLine(to: CGPoint(x: rect.width * 0.72, y: rect.height * 0.50))
    arrow.addLine(to: CGPoint(x: rect.width * 0.52, y: rect.height * 0.55))
    arrow.addLine(to: CGPoint(x: rect.width * 0.42, y: rect.height * 0.76))
    arrow.closeSubpath()
    context.fill(arrow, with: .color(color))
    context.stroke(arrow, with: .color(color), style: StrokeStyle(lineWidth: rect.width * 0.05, lineJoin: .round))
  }

  /// Square brackets around a block cursor.
  private static func brackets(_ context: inout GraphicsContext, _ rect: CGRect, _ color: Color) {
    let style = StrokeStyle(lineWidth: rect.width * 0.12, lineCap: .round, lineJoin: .round)
    var left = Path()
    left.move(to: CGPoint(x: rect.width * 0.34, y: rect.height * 0.16))
    left.addLine(to: CGPoint(x: rect.width * 0.16, y: rect.height * 0.16))
    left.addLine(to: CGPoint(x: rect.width * 0.16, y: rect.height * 0.84))
    left.addLine(to: CGPoint(x: rect.width * 0.34, y: rect.height * 0.84))
    var right = Path()
    right.move(to: CGPoint(x: rect.width * 0.66, y: rect.height * 0.16))
    right.addLine(to: CGPoint(x: rect.width * 0.84, y: rect.height * 0.16))
    right.addLine(to: CGPoint(x: rect.width * 0.84, y: rect.height * 0.84))
    right.addLine(to: CGPoint(x: rect.width * 0.66, y: rect.height * 0.84))
    context.stroke(left, with: .color(color), style: style)
    context.stroke(right, with: .color(color), style: style)
    context.fill(
      Path(roundedRect: CGRect(x: rect.width * 0.42, y: rect.height * 0.34, width: rect.width * 0.16, height: rect.height * 0.32), cornerRadius: 1.5),
      with: .color(color))
  }

  /// A lifted peak with a small orbit: antigravity.
  private static func peak(_ context: inout GraphicsContext, _ rect: CGRect, _ color: Color) {
    var peak = Path()
    peak.move(to: CGPoint(x: rect.width * 0.14, y: rect.height * 0.80))
    peak.addLine(to: CGPoint(x: rect.width * 0.50, y: rect.height * 0.22))
    peak.addLine(to: CGPoint(x: rect.width * 0.86, y: rect.height * 0.80))
    context.stroke(peak, with: .color(color), style: StrokeStyle(lineWidth: rect.width * 0.14, lineCap: .round, lineJoin: .round))
    let orbit = CGRect(x: rect.width * 0.42, y: rect.height * 0.04, width: rect.width * 0.16, height: rect.width * 0.16)
    context.fill(Path(ellipseIn: orbit), with: .color(color.opacity(0.85)))
  }
}
