// DropClipIslandView.swift
// Brim
//
// DropClip inside the open island. DropClip itself works in any app: select text, press the
// shortcut, and a bar of actions appears next to the selection. This page turns it on, gets the
// one permission it needs, and lets you try every action on a sample sentence.

import SwiftUI

@MainActor
struct DropClipIslandView: View {
  @StateObject private var model = DropClipModel()
  @State private var sample = "Select any text, then pick an action. It works the same in every app."
  @State private var enabled: Bool
  @State private var trusted: Bool
  @State private var hovered: DropClipAction?
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  private let shortcut: String
  private let readState: @MainActor () -> (enabled: Bool, trusted: Bool)

  init(
    shortcut: String = AppSettings.shared.dropClipShortcut.display,
    readState: @escaping @MainActor () -> (enabled: Bool, trusted: Bool) = {
      (AppSettings.shared.dropClipEnabled, SelectionReader.isTrusted)
    }
  ) {
    self.shortcut = shortcut
    self.readState = readState
    let state = readState()
    _enabled = State(initialValue: state.enabled)
    _trusted = State(initialValue: state.trusted)
  }

  private var ready: Bool { enabled && trusted }

  var body: some View {
    VStack(alignment: .leading, spacing: IslandSpace.s) {
      setup
      HStack(alignment: .top, spacing: IslandSpace.m) {
        pad.frame(maxWidth: .infinity)
        actions.frame(width: 252)
      }
    }
    .frame(maxWidth: .infinity, alignment: .topLeading)
    .overlay(alignment: .topLeading) { TranslationHost(model: model) }
    .onAppear { begin(); refresh() }
    .onChange(of: sample) { _, _ in begin() }
    .task {
      // Accessibility is granted in System Settings; pick it up as soon as it happens.
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(1.5))
        refresh()
      }
    }
  }

  private func begin() {
    model.begin(SelectionSnapshot(text: sample, bounds: nil, bundleID: nil, appName: nil))
  }

  private func refresh() {
    let state = readState()
    enabled = state.enabled
    trusted = state.trusted
  }

  // MARK: Setup

  @ViewBuilder private var setup: some View {
    HStack(spacing: IslandSpace.s) {
      Image(systemName: ready ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
        .font(.system(size: 16)).foregroundStyle(ready ? Color.green : Color.orange)
      if !enabled {
        Text("DropClip is off.").font(.system(size: 12, weight: .semibold)).foregroundStyle(IslandInk.primary)
        Spacer(minLength: 0)
        Button("Turn On", action: turnOn).buttonStyle(CaptureAppButtonStyle(prominent: true))
      } else if !trusted {
        Text("Needs Accessibility access to read your selection.")
          .font(.system(size: 12, weight: .semibold)).foregroundStyle(IslandInk.primary).lineLimit(1)
        Spacer(minLength: 0)
        Button("Allow", action: allow).buttonStyle(CaptureAppButtonStyle(prominent: true))
      } else {
        Text("Ready. Select text anywhere and press \(shortcut).")
          .font(.system(size: 12, weight: .semibold)).foregroundStyle(IslandInk.primary).lineLimit(1)
        Spacer(minLength: 0)
        Button("Customize…") { SettingsWindowController.shared.show(.tool(.dropClip)) }.buttonStyle(CaptureAppButtonStyle())
      }
    }
    .padding(.horizontal, IslandSpace.m)
    .frame(maxWidth: .infinity, minHeight: 38)
    .glassCard(radius: IslandRadius.medium)
  }

  private func turnOn() {
    AppSettings.shared.dropClipEnabled = true
    DropClipController.shared.settingsChanged()
    refresh()
  }

  private func allow() {
    SelectionReader.requestTrust()
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
      NSWorkspace.shared.open(url)
    }
  }

  // MARK: Try it

  private var pad: some View {
    DropletCard {
      VStack(alignment: .leading, spacing: 6) {
        Text("Try it here").font(.system(size: 12, weight: .semibold)).foregroundStyle(IslandInk.secondary)
        TextEditor(text: $sample).font(.system(size: 12)).scrollContentBackground(.hidden)
          .padding(4).background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: IslandRadius.small))
          .frame(minHeight: 56)
        outcomeLine
      }
      .padding(IslandSpace.s)
      .animation(NotchMotion.feedback(reduceMotion: reduceMotion), value: model.outcome)
    }
  }

  @ViewBuilder private var outcomeLine: some View {
    if let outcome = model.outcome {
      HStack(alignment: .top, spacing: 6) {
        Image(systemName: outcome.symbol).font(.system(size: 12, weight: .bold))
          .foregroundStyle(outcome.isError ? Color.orange : Color.green).padding(.top, 1)
        Text(outcome.body ?? outcome.title).font(.system(size: 12)).foregroundStyle(IslandInk.primary)
          .lineLimit(2).textSelection(.enabled)
        Spacer(minLength: 0)
        if let copyable = outcome.copyable {
          Button("Copy") { DropClipRunner.copy(copyable) }.buttonStyle(CaptureAppButtonStyle())
        }
      }
      .transition(.opacity)
    } else {
      Text("Actions run on this text.").font(.system(size: 12)).foregroundStyle(IslandInk.tertiary)
    }
  }

  private var actions: some View {
    let items = model.actions
    return VStack(alignment: .leading, spacing: 6) {
      Text("Actions on the bar").font(.system(size: 12, weight: .semibold)).foregroundStyle(IslandInk.secondary)
      ScrollView(showsIndicators: false) {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 5), spacing: 6) {
          ForEach(items) { action in
            Button { Task { await model.perform(action) } } label: {
              ZStack {
                if model.runningAction == action {
                  ProgressView().controlSize(.small)
                } else {
                  Image(systemName: action.symbol).font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(hovered == action ? Color.black : Color.purple)
                }
              }
              .frame(maxWidth: .infinity).frame(height: 36)
              .background(hovered == action ? Color.purple : IslandFill.raised,
                          in: RoundedRectangle(cornerRadius: IslandRadius.medium, style: .continuous))
            }
            .buttonStyle(IslandPressStyle())
            .onHover { inside in hovered = inside ? action : (hovered == action ? nil : hovered) }
            .help(model.title(of: action))
            .accessibilityLabel(model.title(of: action))
          }
        }
      }
      Text(hovered.map { model.title(of: $0) } ?? " ")
        .font(.system(size: 12)).foregroundStyle(IslandInk.secondary).lineLimit(1)
        .contentTransition(.opacity).animation(NotchMotion.feedback(reduceMotion: reduceMotion), value: hovered)
    }
  }
}
