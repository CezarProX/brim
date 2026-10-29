import SwiftUI

/// The island card for one agent question or approval. Stateless about the queue: the caller
/// supplies the actions, so the same view renders in tests.
struct AgentQuestionCardView: View {
  static let width: CGFloat = 372

  let request: AgentQuestionRequest
  var waiting = 0
  var onChoose: ([String]) -> Void = { _ in }
  var onReply: (String) -> Void = { _ in }
  var onDecide: (Bool) -> Void = { _ in }
  var onJump: () -> Void = {}
  var onClose: () -> Void = {}

  @State private var text = ""
  @State private var picked: [String] = []
  @FocusState private var typing: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      header
      Text(request.question)
        .font(IslandFont.body).foregroundStyle(IslandInk.primary)
        // Approvals show the whole command (the hook only sends ones that fit, `AgentHook.fitsOnCard`).
        .lineLimit(request.kind == .approval ? nil : 6).fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
      if request.kind == .approval { approvalButtons } else { choices }
      if request.kind == .question && request.allowsText { replyField }
    }
    .padding(16)
    .frame(width: Self.width)
    .glassPanel(radius: 28, shadow: false)
    .environment(\.colorScheme, .dark)
  }

  private var header: some View {
    HStack(spacing: 8) {
      AgentMascot(tool: request.agent, size: 22)
      VStack(alignment: .leading, spacing: 1) {
        Text(request.agent.rawValue).font(IslandFont.headline).foregroundStyle(IslandInk.primary)
        if !request.project.isEmpty {
          Text(request.project).font(IslandFont.caption).foregroundStyle(IslandInk.secondary).lineLimit(1)
        }
      }
      Spacer(minLength: 8)
      if waiting > 0 {
        Text("+\(waiting)").font(IslandFont.caption).monospacedDigit().foregroundStyle(IslandInk.secondary)
          .padding(.horizontal, 7).padding(.vertical, 3).background(IslandFill.subtle, in: Capsule())
      }
      iconButton("terminal", help: "Jump to terminal", action: onJump)
      iconButton("xmark", help: "Close", action: onClose)
    }
  }

  private func iconButton(_ symbol: String, help: LocalizedStringKey, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(IslandInk.secondary)
        .frame(width: 26, height: 26).background(IslandFill.subtle, in: Circle())
    }
    .buttonStyle(.plain).help(help)
  }

  private var choices: some View {
    VStack(spacing: 6) {
      ForEach(Array(request.options.enumerated()), id: \.offset) { _, option in
        let selected = picked.contains(option.label)
        Button {
          if request.multiSelect {
            picked = selected ? picked.filter { $0 != option.label } : picked + [option.label]
          } else {
            onChoose([option.label])
          }
        } label: {
          HStack(spacing: 8) {
            if request.multiSelect {
              Image(systemName: selected ? "checkmark.circle.fill" : "circle").foregroundStyle(selected ? Color.accentColor : IslandInk.tertiary)
            }
            VStack(alignment: .leading, spacing: 1) {
              Text(verbatim: option.label).font(IslandFont.headline).foregroundStyle(IslandInk.primary).lineLimit(2)
              if let detail = option.detail {
                Text(verbatim: detail).font(IslandFont.caption).foregroundStyle(IslandInk.secondary).lineLimit(2)
              }
            }
            Spacer(minLength: 0)
          }
          .padding(.horizontal, 12).padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
          .background(selected ? IslandFill.selected : IslandFill.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
      }
      if request.multiSelect {
        Button { onChoose(picked) } label: {
          Text("Send").font(IslandFont.headline).foregroundStyle(.black).frame(maxWidth: .infinity).padding(.vertical, 8)
            .background(picked.isEmpty ? Color.white.opacity(0.35) : Color.white, in: Capsule())
        }
        .buttonStyle(.plain).disabled(picked.isEmpty)
      }
    }
  }

  private var approvalButtons: some View {
    HStack(spacing: 8) {
      Button { onDecide(false) } label: {
        Text("Deny").font(IslandFont.headline).foregroundStyle(IslandInk.primary).frame(maxWidth: .infinity).padding(.vertical, 9)
          .background(IslandFill.raised, in: Capsule())
      }
      .buttonStyle(.plain)
      Button { onDecide(true) } label: {
        Text("Allow").font(IslandFont.headline).foregroundStyle(.black).frame(maxWidth: .infinity).padding(.vertical, 9)
          .background(Color.white, in: Capsule())
      }
      .buttonStyle(.plain)
    }
  }

  private var replyField: some View {
    HStack(spacing: 8) {
      TextField("Type a reply", text: $text)
        .textFieldStyle(.plain).font(IslandFont.body).foregroundStyle(IslandInk.primary)
        .focused($typing).onSubmit(submit)
      Button(action: submit) {
        Image(systemName: "arrow.up.circle.fill").font(.system(size: 20))
          .foregroundStyle(text.trimmingCharacters(in: .whitespaces).isEmpty ? IslandInk.tertiary : Color.white)
      }
      .buttonStyle(.plain).disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
    }
    .padding(.horizontal, 12).padding(.vertical, 7)
    .background(IslandFill.subtle, in: Capsule())
  }

  private func submit() {
    guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
    onReply(text)
  }
}
