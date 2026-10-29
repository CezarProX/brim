import SwiftUI

/// What the tour card shows; `IslandTourController` updates it.
@MainActor
final class IslandTourCardModel: ObservableObject {
  @Published var step: IslandTourStep = .open
  @Published var context = IslandTourContext()
  /// Drives the card's arrival and departure (a short drop and fade under the island).
  @Published var visible = false
}

extension IslandTourStep {
  var symbol: String {
    switch self {
    case .open: "cursorarrow.motionlines"
    case .home: "house.fill"
    case .clipboard: "doc.on.clipboard.fill"
    case .music: "music.note"
    case .widgets: "square.grid.2x2.fill"
    case .tray: "tray.fill"
    case .swipe: "hand.draw.fill"
    case .rightClick: "contextualmenu.and.cursorarrow"
    case .closed: "capsule.fill"
    case .done: "checkmark"
    }
  }
}

/// The Island Tour's coach mark: a small dark-glass card under the island with the step, a line or
/// two of help, "2 / 9", and Back / Next / Skip tour. Steps that wait for the user say "Try it now".
struct IslandTourCard: View {
  static let width: CGFloat = 340

  @ObservedObject var model: IslandTourCardModel
  var back: () -> Void = {}
  var next: () -> Void = {}
  var skip: () -> Void = {}
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var step: IslandTourStep { model.step }
  private var isFirst: Bool { step == IslandTourStep.allCases.first }
  private var isLast: Bool { step == IslandTourStep.allCases.last }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      VStack(alignment: .leading, spacing: 8) {
        header
        ForEach(step.lines(model.context), id: \.self) { line in
          Text(line)
            .font(.system(size: 12.5))
            .foregroundStyle(IslandInk.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        if step.waitsForAction(model.context) {
          Label("Try it now", systemImage: "hand.point.up.left.fill")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(IslandInk.tertiary)
            .labelStyle(.titleAndIcon)
            .padding(.top, 2)
        }
      }
      .id(step)
      .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 5)))
      footer
    }
    .padding(16)
    .frame(width: Self.width, alignment: .leading)
    .glassPanel(radius: 22, shadow: false)
    .foregroundStyle(IslandInk.primary)
    .environment(\.colorScheme, .dark)
    .scaleEffect(model.visible || reduceMotion ? 1 : 0.94, anchor: .top)
    .offset(y: model.visible || reduceMotion ? 0 : -8)
    .opacity(model.visible ? 1 : 0)
    .padding(IslandTourLayout.shadowMargin)
    .accessibilityElement(children: .contain)
  }

  private var header: some View {
    HStack(spacing: 9) {
      Image(systemName: step.symbol)
        .font(.system(size: 11, weight: .bold))
        .frame(width: 24, height: 24)
        .background(Color.white.opacity(0.14), in: Circle())
      Text(step.title)
        .font(.system(size: 14, weight: .semibold))
        .accessibilityAddTraits(.isHeader)
      Spacer(minLength: 8)
      Text(verbatim: "\(step.rawValue + 1) / \(IslandTourSession.count)")
        .font(.system(size: 11, weight: .medium)).monospacedDigit()
        .foregroundStyle(IslandInk.tertiary)
    }
  }

  private var footer: some View {
    HStack(spacing: 8) {
      if isLast {
        Spacer(minLength: 0)
      } else {
        Button("Skip tour", action: skip)
          .buttonStyle(IslandTourButtonStyle(kind: .plain))
          .fixedSize()
        Spacer(minLength: 0)
      }
      if !isFirst {
        Button("Back", action: back)
          .buttonStyle(IslandTourButtonStyle(kind: .secondary))
          .fixedSize()
      }
      Button(isLast ? "Done" : "Next", action: next)
        .buttonStyle(IslandTourButtonStyle(kind: .primary))
        .fixedSize()
    }
  }
}

/// Small capsule buttons in the island's ink: white for Next, frosted for Back, bare text for Skip.
private struct IslandTourButtonStyle: ButtonStyle {
  enum Kind { case primary, secondary, plain }
  let kind: Kind
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 12, weight: kind == .plain ? .medium : .semibold))
      .foregroundStyle(kind == .primary ? Color.black : kind == .plain ? IslandInk.tertiary : IslandInk.primary)
      .padding(.horizontal, kind == .plain ? 2 : 13)
      .frame(height: 26)
      .background {
        switch kind {
        case .primary: Capsule().fill(Color.white)
        case .secondary: Capsule().fill(Color.white.opacity(0.14))
        case .plain: EmptyView()
        }
      }
      .contentShape(Capsule())
      .scaleEffect(configuration.isPressed ? 0.94 : 1)
      .animation(NotchMotion.press(reduceMotion: reduceMotion), value: configuration.isPressed)
  }
}
