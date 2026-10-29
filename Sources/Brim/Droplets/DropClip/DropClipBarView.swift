// DropClipBarView.swift
// Brim
//
// The floating action bar: a row of icon buttons and, below it, the result of the last action.

import SwiftUI
import Translation

struct DropClipBarView: View {
  @ObservedObject var model: DropClipModel
  var onClose: () -> Void = {}

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 2) {
        ForEach(model.actions) { action in
          BarButton(action: action, model: model, running: model.runningAction == action, onClose: onClose)
        }
      }
      .padding(5)
      if let outcome = model.outcome {
        Divider().overlay(IslandFill.hairline)
        ResultStrip(outcome: outcome).transition(.opacity.combined(with: .move(edge: .top)))
      }
    }
    .frame(minWidth: 120, maxWidth: 420, alignment: .leading)
    .fixedSize(horizontal: true, vertical: true)
    .background(Color.black.opacity(0.92), in: RoundedRectangle(cornerRadius: IslandRadius.medium + 2, style: .continuous))
    .overlay { RoundedRectangle(cornerRadius: IslandRadius.medium + 2, style: .continuous).strokeBorder(IslandFill.selected.opacity(0.7), lineWidth: 0.75) }
    .overlay(alignment: .topLeading) { TranslationHost(model: model) }
    .preferredColorScheme(.dark)
    .animation(.snappy(duration: 0.22), value: model.outcome)
    .padding(6)  // room for the panel shadow
  }
}

private struct BarButton: View {
  let action: DropClipAction
  @ObservedObject var model: DropClipModel
  let running: Bool
  let onClose: () -> Void
  @State private var hovered = false

  var body: some View {
    Button {
      Task {
        await model.perform(action)
        if action == .copy { try? await Task.sleep(for: .milliseconds(450)); onClose() }
      }
    } label: {
      ZStack {
        if running { ProgressView().controlSize(.mini) } else {
          Image(systemName: action.symbol).font(.system(size: 13, weight: .semibold))
            .foregroundStyle(hovered ? IslandInk.primary : IslandInk.secondary)
        }
      }
      .frame(width: 30, height: 28)
      .background(hovered ? IslandFill.hover : .clear, in: RoundedRectangle(cornerRadius: IslandRadius.small, style: .continuous))
      .contentShape(Rectangle())
    }
    .buttonStyle(IslandPressStyle(pressedScale: 0.88))
    .onHover { hovered = $0 }
    .help(model.title(of: action))
    .accessibilityLabel(model.title(of: action))
  }
}

private struct ResultStrip: View {
  let outcome: DropClipOutcome

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 6) {
        Image(systemName: outcome.symbol).font(.system(size: 10, weight: .bold))
          .foregroundStyle(outcome.isError ? Color.orange : Color.green)
        Text(outcome.title).font(IslandFont.label).foregroundStyle(IslandInk.secondary).lineLimit(1)
        Spacer(minLength: 8)
        if let copyable = outcome.copyable {
          Button("Copy") { DropClipRunner.copy(copyable) }.buttonStyle(IslandPillStyle(compact: true))
        }
      }
      if let body = outcome.body {
        ScrollView {
          Text(body).font(.system(size: 12)).foregroundStyle(IslandInk.primary)
            .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
        }
        .frame(maxHeight: 130)
      }
    }
    .padding(.horizontal, 10).padding(.vertical, 8)
    .frame(width: 400, alignment: .leading)
  }
}

/// Runs the on-device Translation session (macOS 15+). Invisible; lives in the bar's hierarchy.
struct TranslationHost: View {
  @ObservedObject var model: DropClipModel

  var body: some View {
    if #available(macOS 15.0, *) { Modern(model: model) } else { Color.clear.frame(width: 0, height: 0) }
  }

  @available(macOS 15.0, *)
  private struct Modern: View {
    @ObservedObject var model: DropClipModel
    @State private var configuration: TranslationSession.Configuration?

    var body: some View {
      Color.clear.frame(width: 0, height: 0)
        .translationTask(configuration) { session in
          let text = model.text
          do {
            let response = try await session.translate(text)
            model.setTranslation(response.targetText, error: nil)
          } catch {
            model.setTranslation(nil, error: error.localizedDescription)
          }
        }
        .onChange(of: model.translationRequest) { _, _ in
          if configuration == nil {
            configuration = .init(source: nil, target: model.translationTarget)
          } else {
            configuration?.invalidate()
          }
        }
    }
  }
}
