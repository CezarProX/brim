import AppKit
import SwiftUI

/// The front browser's identity on the left, its live tab and navigation on the right.
struct BrowserSkinView: View {
  @ObservedObject var model: BrowserSkinModel

  var body: some View {
    VStack(alignment: .leading, spacing: IslandSpace.m) {
      if let snapshot = model.snapshot {
        HStack(spacing: IslandSpace.m) {
          BrowserIcon(browser: snapshot.browser).frame(width: 34, height: 34)
          VStack(alignment: .leading, spacing: 2) {
            Text(snapshot.active.title.isEmpty ? snapshot.browser.name : snapshot.active.title)
              .font(IslandFont.title).lineLimit(1)
              .contentTransition(.opacity)
            Text("\(snapshot.active.host) · \(snapshot.tabCount) tabs")
              .font(IslandFont.label).foregroundStyle(IslandInk.tertiary).lineLimit(1)
          }
          Spacer()
        }
        HStack(spacing: IslandSpace.s) {
          IslandControlButton(title: "Back", symbol: "chevron.left", showsTitle: false, diameter: 34) {
            model.perform(.back)
          }
          IslandControlButton(title: "Forward", symbol: "chevron.right", showsTitle: false, diameter: 34) {
            model.perform(.forward)
          }
          IslandControlButton(title: "Reload", symbol: "arrow.clockwise", showsTitle: false, diameter: 34) {
            model.perform(.reload)
          }
          IslandControlButton(title: "New tab", symbol: "plus", showsTitle: false, diameter: 34) {
            model.perform(.newTab)
          }
          Spacer()
        }
        if !snapshot.others.isEmpty {
          VStack(alignment: .leading, spacing: 4) {
            ForEach(snapshot.others.prefix(3)) { tab in
              HStack(spacing: 6) {
                Circle().fill(IslandInk.tertiary).frame(width: 4, height: 4)
                Text(tab.title.isEmpty ? tab.host : tab.title).font(IslandFont.label).lineLimit(1)
                Text(tab.host).font(IslandFont.caption).foregroundStyle(IslandInk.tertiary).lineLimit(1)
              }
            }
          }
          .transition(.islandDrop)
        }
        if let message = model.message {
          Text(message).font(IslandFont.caption).foregroundStyle(.orange).lineLimit(2)
        }
      } else if model.needsPermission, let browser = model.frontBrowser {
        IslandHeader(
          title: browser.name, symbol: "safari.fill", tint: .blue,
          subtitle: "Allow Brim to read the current tab")
        Button("Allow \(browser.name)") { model.connect() }
          .buttonStyle(IslandPillStyle(prominent: true, tint: .blue))
      } else {
        IslandHeader(title: "Browser", symbol: "safari.fill", tint: .blue, subtitle: "Bring a browser to the front")
      }
    }
    .animation(NotchMotion.layout(reduceMotion: false), value: model.snapshot)
  }
}

struct BrowserIcon: View {
  let browser: SkinBrowser

  var body: some View {
    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: browser.rawValue) {
      Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().scaledToFit()
    } else {
      Image(systemName: "safari.fill").resizable().scaledToFit().foregroundStyle(.blue)
    }
  }
}

private func agentTint(_ session: CodingAgentSession) -> Color { AgentBrand.color(session.tool) }

/// Orange while the agent waits on the user, green once done, the brand color while working.
private func statusTint(_ session: CodingAgentSession) -> Color {
  session.needsAttention ? .orange : session.isWorking ? agentTint(session) : .green
}

/// A live Claude Code or Codex session, laid out like a Live Activity: one card for the session shown
/// (who, what it's doing now, what it just did, the numbers), then one row per other live session.
struct CodingAgentView<Trailing: View>: View {
  let session: CodingAgentSession
  /// Every live session, so parallel projects get a row each instead of taking turns.
  var sessions: [CodingAgentSession] = []
  var pinnedID: String?
  var onSelect: (String) -> Void = { _ in }
  /// Plan usage for this session's agent, when known.
  var usage: UsageReading?
  /// Controls at the end of the card's bottom row, e.g. the answer switch.
  let trailing: Trailing
  @State private var headerHovered = false

  init(
    session: CodingAgentSession, sessions: [CodingAgentSession] = [], pinnedID: String? = nil,
    onSelect: @escaping (String) -> Void = { _ in }, usage: UsageReading? = nil, @ViewBuilder trailing: () -> Trailing
  ) {
    self.session = session
    self.sessions = sessions
    self.pinnedID = pinnedID
    self.onSelect = onSelect
    self.usage = usage
    self.trailing = trailing()
  }

  private var tint: Color { agentTint(session) }
  private var others: [CodingAgentSession] { sessions.filter { $0.id != session.id } }
  /// With other sessions listed underneath, the card keeps to the essentials.
  private var roomy: Bool { others.isEmpty }

  var body: some View {
    VStack(alignment: .leading, spacing: IslandSpace.s) {
      card
      ForEach(others, id: \.id) { item in
        AgentSessionRow(session: item) { onSelect(item.id) }
          .transition(.islandContent)
      }
    }
    .frame(maxWidth: .infinity, alignment: .topLeading)
    .animation(.spring(duration: 0.4, bounce: 0.1), value: session.steps)
    .animation(.spring(duration: 0.4, bounce: 0.1), value: session.isWorking)
    .animation(.spring(duration: 0.4, bounce: 0.1), value: session.id)
  }

  private var card: some View {
    VStack(alignment: .leading, spacing: IslandSpace.m) {
      header
      if session.needsAttention {
        attention
      } else if session.isWorking {
        steps
      } else {
        reply
      }
      footer
    }
    .padding(IslandSpace.m)
    .background(IslandFill.subtle, in: RoundedRectangle(cornerRadius: IslandRadius.large, style: .continuous))
  }

  /// Glyph, project and model; the whole thing opens the session's app.
  private var header: some View {
    HStack(spacing: 10) {
      Button {
        CodingAgentLocator.open(session)
      } label: {
        HStack(spacing: 10) {
          AgentGlyph(tool: session.tool, size: 30, usageFraction: usage?.fraction, attention: session.needsAttention)
          VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
              Text(session.title ?? session.project ?? session.tool.rawValue).font(IslandFont.title).lineLimit(1)
              Image(systemName: "arrow.up.forward").font(.system(size: 9, weight: .bold))
                .foregroundStyle(IslandInk.tertiary).opacity(headerHovered ? 1 : 0)
            }
            HStack(spacing: 4) {
              if session.title != nil, let project = session.project {
                Text(project)
                Text("·")
              }
              Text(session.model ?? session.tool.rawValue)
              if let started = session.started {
                Text("·")
                Text(started, style: .timer).monospacedDigit()
              }
            }
            .font(IslandFont.caption).foregroundStyle(IslandInk.tertiary).lineLimit(1)
          }
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(IslandPressStyle(pressedScale: 0.97))
      .onHover { headerHovered = $0 }
      .help(usage.map { "Open the app this session runs in · 5h plan \($0.percent)%" } ?? "Open the app this session runs in")
      .accessibilityLabel("Open session")
      Spacer(minLength: IslandSpace.s)
      if session.id == pinnedID {
        Button { onSelect(session.id) } label: {
          Image(systemName: "pin.fill").font(.system(size: 10, weight: .semibold)).foregroundStyle(IslandInk.secondary)
            .frame(width: 24, height: 24).contentShape(Rectangle())
        }
        .buttonStyle(IslandPressStyle(pressedScale: 0.88))
        .help("Pinned. Click to follow the latest session again.")
      }
      AgentStatusLabel(session: session)
    }
  }

  /// The agent is blocked: say on what, and make it one tap to answer.
  private var attention: some View {
    HStack(spacing: 10) {
      Image(systemName: "hand.raised.fill").font(.system(size: 12, weight: .semibold)).foregroundStyle(.orange)
        .frame(width: 28, height: 28).background(Color.orange.opacity(0.16), in: Circle())
      VStack(alignment: .leading, spacing: 1) {
        Text(session.stateTitle).font(IslandFont.headline).lineLimit(2)
        Text(session.currentFile.map { "Waiting in \($0)" } ?? "Waiting for you in \(session.tool.rawValue)")
          .font(IslandFont.caption).foregroundStyle(IslandInk.tertiary).lineLimit(1)
      }
      Spacer(minLength: 0)
      Button("Open") { CodingAgentLocator.open(session) }
        .buttonStyle(IslandPillStyle(prominent: true, tint: .orange))
    }
    .padding(10)
    .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: IslandRadius.medium, style: .continuous))
    .transition(.islandContent)
  }

  /// What it's doing now, big; the steps before it as a quiet trail; then what it last said.
  private var steps: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 10) {
        Image(systemName: session.steps.first.map(CodingAgentParser.symbol(for:)) ?? "sparkle")
          .font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
          .frame(width: 28, height: 28).background(tint, in: Circle())
          .contentTransition(.symbolEffect(.replace))
        Text(session.steps.first.map(CodingAgentParser.headline(for:)) ?? "Thinking…")
          .font(IslandFont.headline).foregroundStyle(IslandInk.primary).lineLimit(1)
          .contentTransition(.opacity)
      }
      ForEach(Array(session.steps.dropFirst().prefix(roomy ? 2 : 1).enumerated()), id: \.offset) { _, step in
        HStack(spacing: 10) {
          Image(systemName: CodingAgentParser.symbol(for: step)).font(.system(size: 9, weight: .semibold))
            .frame(width: 28)
          Text(CodingAgentParser.headline(for: step)).font(IslandFont.label).lineLimit(1)
        }
        .foregroundStyle(IslandInk.tertiary)
        .transition(.islandDrop)
      }
      if roomy, let message = session.lastMessage {
        Text(message).font(.system(size: 12)).foregroundStyle(IslandInk.secondary).lineLimit(2)
          .fixedSize(horizontal: false, vertical: true)
          .padding(.top, 4)
      }
    }
    .transition(.islandContent)
  }

  /// When it's your turn, what the agent said is the point.
  private var reply: some View {
    Text(session.lastMessage ?? "Finished. Waiting for your next message.")
      .font(.system(size: 13)).foregroundStyle(IslandInk.primary)
      .lineLimit(roomy ? 5 : 2).multilineTextAlignment(.leading)
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: .infinity, alignment: .topLeading)
      .transition(.islandContent)
  }

  private var contextFraction: Double? {
    session.contextFraction ?? (session.contextTokens > 0
      ? min(1, Double(session.contextTokens) / Double(CodingAgentParser.contextWindow(for: session.contextTokens))) : nil)
  }

  /// Context, lines changed, and plan usage only once it's close to the limit; controls on the right.
  private var footer: some View {
    HStack(spacing: IslandSpace.m) {
      if let fraction = contextFraction {
        HStack(spacing: 5) {
          AgentUsageRing(fraction: fraction, tint: fraction > 0.8 ? .orange : IslandInk.secondary, lineWidth: 2)
            .frame(width: 11, height: 11)
          Text("Context \(Int((fraction * 100).rounded()))%")
        }
        .help("Share of the context window used")
      }
      if session.hasLineChanges {
        HStack(spacing: 4) {
          Text("+\(session.linesAdded)").foregroundStyle(Color.green.opacity(0.85))
          Text("−\(session.linesRemoved)").foregroundStyle(Color.red.opacity(0.8))
        }
      }
      if let usage, usage.fraction >= 0.8 {
        Text("5h \(usage.percent)%").foregroundStyle(AgentUsageRing.color(fraction: usage.fraction, base: tint))
          .help(usage.resetsAt.map { "Resets \($0.formatted(date: .omitted, time: .shortened))" } ?? "Plan usage")
      }
      Spacer(minLength: 0)
      trailing
    }
    .font(IslandFont.caption).monospacedDigit().foregroundStyle(IslandInk.tertiary)
    .frame(minHeight: 28)
  }
}

extension CodingAgentView where Trailing == EmptyView {
  init(
    session: CodingAgentSession, sessions: [CodingAgentSession] = [], pinnedID: String? = nil,
    onSelect: @escaping (String) -> Void = { _ in }, usage: UsageReading? = nil
  ) {
    self.init(session: session, sessions: sessions, pinnedID: pinnedID, onSelect: onSelect, usage: usage) { EmptyView() }
  }
}

/// A colored dot and the session's state in a word.
private struct AgentStatusLabel: View {
  let session: CodingAgentSession

  var body: some View {
    HStack(spacing: 5) {
      Circle().fill(statusTint(session)).frame(width: 6, height: 6)
      Text(session.statusText).font(IslandFont.label.weight(.semibold)).contentTransition(.opacity)
    }
    .foregroundStyle(statusTint(session))
  }
}

/// Another live session, one row: tap to show it in the card above.
private struct AgentSessionRow: View {
  let session: CodingAgentSession
  let select: () -> Void
  @State private var hovered = false

  var body: some View {
    Button(action: select) {
      HStack(spacing: 10) {
        AgentGlyph(tool: session.tool, size: 22, attention: session.needsAttention)
        VStack(alignment: .leading, spacing: 1) {
          HStack(spacing: 6) {
            Text(name).font(IslandFont.headline).foregroundStyle(IslandInk.primary).layoutPriority(1)
            if session.title != nil, let project = session.project {
              Text(project).font(IslandFont.caption).foregroundStyle(IslandInk.tertiary)
            }
          }
          Text(detail).font(IslandFont.caption).foregroundStyle(IslandInk.tertiary)
        }
        .lineLimit(1)
        Spacer(minLength: IslandSpace.s)
        AgentStatusLabel(session: session)
      }
      .padding(.horizontal, IslandSpace.m)
      .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
      .background(hovered ? IslandFill.raised : IslandFill.subtle, in: RoundedRectangle(cornerRadius: IslandRadius.medium, style: .continuous))
      .contentShape(RoundedRectangle(cornerRadius: IslandRadius.medium, style: .continuous))
    }
    .buttonStyle(IslandPressStyle(pressedScale: 0.98))
    .onHover { hovered = $0 }
    .help("Show \(name)")
    .accessibilityLabel(name)
    .accessibilityValue(session.statusText)
  }

  private var name: String { session.title ?? session.project ?? session.tool.rawValue }

  private var detail: String {
    if session.needsAttention { return session.stateTitle }
    if session.isWorking { return session.steps.first.map(CodingAgentParser.headline(for:)) ?? "Thinking…" }
    return session.lastMessage ?? session.model ?? session.tool.rawValue
  }
}

/// The compact notch's right wing for an agent: moving dots while it works, a green check when it's
/// your turn, and how many sessions are live. Motion runs in Core Animation so SwiftUI never
/// re-renders the notch per frame (a continuous SwiftUI animation cost ~14% CPU there).
struct AgentStateIndicator: View {
  let session: CodingAgentSession
  var liveCount = 1

  var body: some View {
    HStack(spacing: 4) {
      if session.needsAttention {
        Image(systemName: "hand.raised.fill")
          .font(.system(size: 13, weight: .semibold)).foregroundStyle(.orange)
          .background { AgentAttentionPulse(color: .orange).frame(width: 24, height: 24) }
          .transition(.scale.combined(with: .opacity))
      } else if session.isWorking {
        AgentWorkingDots(tint: agentTint(session)).frame(width: 20, height: 8)
          .transition(.scale.combined(with: .opacity))
      } else {
        Image(systemName: "checkmark.circle.fill")
          .font(.system(size: 14, weight: .semibold)).foregroundStyle(.green)
          .transition(.scale.combined(with: .opacity))
      }
      if liveCount > 1 {
        Text("\(liveCount)").font(IslandFont.caption.weight(.bold)).monospacedDigit()
          .foregroundStyle(IslandInk.secondary)
      }
    }
    .animation(.spring(duration: 0.35, bounce: 0.35), value: session.state)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(session.statusText)
  }
}

/// Three dots fading in sequence, animated by Core Animation, not SwiftUI.
private struct AgentWorkingDots: NSViewRepresentable {
  let tint: Color

  func makeNSView(context: Context) -> NSView {
    let view = NSView()
    view.wantsLayer = true
    let size: CGFloat = 5
    for index in 0..<3 {
      let dot = CALayer()
      dot.frame = CGRect(x: CGFloat(index) * 7.5, y: 1.5, width: size, height: size)
      dot.cornerRadius = size / 2
      dot.backgroundColor = NSColor(tint).cgColor
      let pulse = CAKeyframeAnimation(keyPath: "opacity")
      pulse.values = [0.25, 1, 0.25]
      pulse.keyTimes = [0, 0.5, 1]
      pulse.duration = 1.1
      pulse.beginTime = CACurrentMediaTime() + Double(index) * 0.18
      pulse.repeatCount = .infinity
      dot.opacity = 0.25
      dot.add(pulse, forKey: "pulse")
      view.layer?.addSublayer(dot)
    }
    return view
  }

  func updateNSView(_ view: NSView, context: Context) {
    view.layer?.sublayers?.forEach { $0.backgroundColor = NSColor(tint).cgColor }
  }
}
