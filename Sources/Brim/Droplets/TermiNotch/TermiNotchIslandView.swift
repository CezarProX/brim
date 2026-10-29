// TermiNotchIslandView.swift
// Brim
//
// The Termi-Notch droplet: tabs, a terminal canvas, history and the external-terminal hand-off.

import AppKit
import SwiftUI

struct TermiNotchIslandView: View {
  /// True inside the open island; false in the drop-down panel (no subtitle there).
  var compact = true
  @ObservedObject private var model: TermiNotchModel

  @MainActor init(compact: Bool = true, model: TermiNotchModel? = nil) {
    self.compact = compact
    self.model = model ?? .shared
  }
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      VStack(spacing: 0) {
        toolbar
        Divider().overlay(IslandFill.hairline)
        if let session = model.selected {
          TerminalCanvasView(session: session, fontSize: model.fontSize)
            .id(session.id)
            .overlay(alignment: .bottomLeading) { FirstRunHint(session: session) }
            .transition(.opacity)
        } else {
          emptyState
        }
      }
      .background(Color.black.opacity(compact ? 0.45 : 0), in: RoundedRectangle(cornerRadius: IslandRadius.medium, style: .continuous))
      .clipShape(RoundedRectangle(cornerRadius: IslandRadius.medium, style: .continuous))
    }
    .frame(minWidth: compact ? 520 : 0, minHeight: compact ? 190 : 0)
    .onAppear { model.ensureTab() }
    .animation(NotchMotion.layout(reduceMotion: reduceMotion), value: model.selectedID)
  }

  private var toolbar: some View {
    HStack(spacing: IslandSpace.s) {
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 4) {
          ForEach(model.tabs) { tab in TabPill(session: tab, model: model, selected: tab.id == model.selected?.id) }
        }
      }
      DropletIconButton(symbol: "plus", help: "New tab (⌘T)", size: 28) { model.newTab() }
      Spacer(minLength: 0)
      DropletIconButton(symbol: "doc.on.doc", help: "Copy all output", size: 28) { copyOutput() }
        .disabled(model.selected == nil)
      DropletIconButton(symbol: "eraser", help: "Clear output (⌘K)", size: 28) { model.selected?.clearOutput() }
        .disabled(model.selected == nil)
      historyButton
      Menu {
        ForEach(ExternalTerminal.allCases) { app in
          Button("Open in \(app.title)") { model.handOff(to: app) }.disabled(app.appURL == nil)
        }
      } label: {
        Image(systemName: "arrow.up.forward.app").font(.system(size: 12, weight: .semibold))
          .foregroundStyle(IslandInk.secondary).frame(width: 28, height: 28)
          .background(IslandFill.subtle, in: Circle())
      }
      .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 28)
      .help("Open this folder in Terminal, iTerm or Warp")
    }
    .padding(.horizontal, IslandSpace.s).padding(.vertical, 4)
  }

  private func copyOutput() {
    guard let text = model.selected?.outputText, !text.isEmpty else { return }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
    IslandFlashCenter.shared.show(L10n.tr("Output copied"), symbol: "doc.on.doc.fill", tint: .green)
  }

  private var historyButton: some View {
    DropletIconButton(symbol: "clock.arrow.circlepath", help: "Command history", size: 28) { model.showsHistory.toggle() }
      .popover(isPresented: $model.showsHistory, arrowEdge: .bottom) {
        HistoryList(session: model.selected) { command in
          model.selected?.insertWithoutRunning(command)
          model.showsHistory = false
        }
      }
  }

  private var emptyState: some View {
    VStack(spacing: 8) {
      Image(systemName: "terminal").font(.system(size: 24, weight: .light)).foregroundStyle(IslandInk.tertiary)
      Text("No terminal open").font(IslandFont.headline).foregroundStyle(IslandInk.secondary)
      Button("New tab") { model.newTab() }.buttonStyle(IslandAppPillStyle(prominent: true, tint: .green))
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

/// Shown under the first prompt of a fresh tab: say what to do, and offer starter commands that are
/// only typed onto the line, never run.
struct FirstRunHint: View {
  @ObservedObject var session: TerminalSession
  static let starters = ["ls -la", "pwd", "git status", "df -h"]

  var body: some View {
    if session.isAlive, !session.hasInput, session.buffer.isFresh {
      VStack(alignment: .leading, spacing: 6) {
        Text("Type a command and press Return. These only fill in the line:")
          .font(.system(size: 12)).foregroundStyle(IslandInk.secondary)
        HStack(spacing: 6) {
          ForEach(Self.starters, id: \.self) { command in
            Button { session.insertWithoutRunning(command) } label: {
              Text(command).font(.system(size: 12, design: .monospaced)).foregroundStyle(IslandInk.primary)
                .padding(.horizontal, 10).frame(height: 28)
                .background(IslandFill.raised, in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(IslandPressStyle(pressedScale: 0.94))
            .accessibilityLabel("Type \(command) without running it")
          }
        }
      }
      .padding(.horizontal, 12).padding(.bottom, 10)
      .transition(.opacity)
    }
  }
}

private struct TabPill: View {
  @ObservedObject var session: TerminalSession
  @ObservedObject var model: TermiNotchModel
  let selected: Bool
  @State private var hovered = false

  var body: some View {
    HStack(spacing: 6) {
      Circle().fill(session.isAlive ? Color.green : IslandInk.tertiary).frame(width: 6, height: 6)
      Text(session.title).font(.system(size: 12, weight: .medium)).lineLimit(1).frame(maxWidth: 120)
      if hovered || selected {
        Button { model.close(session) } label: {
          Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).frame(width: 18, height: 18).contentShape(Rectangle())
        }
        .buttonStyle(.plain).help("Close tab (⌘W)").accessibilityLabel("Close tab")
      }
    }
    .foregroundStyle(selected ? IslandInk.primary : IslandInk.secondary)
    .padding(.horizontal, 10).frame(height: 28)
    .background(selected ? IslandFill.selected : (hovered ? IslandFill.hover : IslandFill.subtle), in: Capsule())
    .contentShape(Capsule())
    .onTapGesture { model.selectedID = session.id }
    .onHover { hovered = $0 }
  }
}

private struct HistoryList: View {
  let session: TerminalSession?
  let insert: (String) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("History").font(.headline)
      if let history = session?.history, !history.isEmpty {
        ScrollView {
          VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(history.enumerated().reversed()), id: \.offset) { _, command in
              Button { insert(command) } label: {
                Text(command).font(.system(size: 12, design: .monospaced)).lineLimit(1)
                  .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading).contentShape(Rectangle())
              }
              .buttonStyle(.plain)
            }
          }
        }
        .frame(maxHeight: 180)
        Text("Click to put a command on the line. It runs only when you press Return.")
          .font(.caption).foregroundStyle(.secondary)
      } else {
        Text("Commands you run in this tab appear here.").font(.caption).foregroundStyle(.secondary)
      }
    }
    .padding(12).frame(width: 300)
  }
}
