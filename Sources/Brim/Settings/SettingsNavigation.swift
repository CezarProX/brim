// SettingsNavigation.swift
// Brim
//
// Where the Settings window is looking: the sidebar page, a drilled-in tool page (Home & Widgets >
// Weather) and a row to scroll to and highlight. Anything in the app that sends the user to Settings
// goes through `SettingsWindowController.show(_:)` with a `SettingsDestination`, so it lands on the
// exact control instead of a page the user has to search.

import SwiftUI

/// Basic rows shown up front, or the rarely needed ones under a page's Advanced disclosure.
enum SettingsPart: Hashable, Sendable { case basic, advanced }

/// A place in Settings: a page, optionally a tool page inside Home & Widgets, optionally a row.
struct SettingsDestination: Hashable, Sendable {
  var pane: SettingsPane
  var tool: SettingsTool?
  /// The `settingsAnchor` id of the row to scroll to and highlight.
  var anchor: String?

  init(_ pane: SettingsPane, tool: SettingsTool? = nil, anchor: String? = nil) {
    self.pane = tool == nil ? pane : .widgets
    self.tool = tool
    self.anchor = anchor
  }

  static func tool(_ tool: SettingsTool, anchor: String? = nil) -> SettingsDestination {
    SettingsDestination(.widgets, tool: tool, anchor: anchor)
  }
}

/// The Settings window's navigation state. One shared instance drives the real window; tests make
/// their own.
@MainActor
final class SettingsNavigator: ObservableObject {
  static let shared = SettingsNavigator()

  @Published var pane: SettingsPane
  @Published var toolPath: [SettingsTool]
  /// The row being pointed at; cleared a moment after it has been highlighted.
  @Published private(set) var highlight: String?
  /// The row the last deep link pointed at. It keeps an Advanced group open after the highlight
  /// fades, until the user goes to another page.
  @Published private(set) var deepLinkAnchor: String?

  init(_ destination: SettingsDestination = SettingsDestination(.general)) {
    pane = destination.pane
    toolPath = destination.tool.map { [$0] } ?? []
    highlight = destination.anchor
    deepLinkAnchor = destination.anchor
  }

  func open(_ destination: SettingsDestination) {
    pane = destination.pane
    toolPath = destination.tool.map { [$0] } ?? []
    highlight = destination.anchor
    deepLinkAnchor = destination.anchor
  }

  func select(_ pane: SettingsPane) {
    guard pane != self.pane || !toolPath.isEmpty else { return }
    self.pane = pane
    toolPath = []
    highlight = nil
    deepLinkAnchor = nil
  }

  /// Lets an Advanced group that a deep link opened be closed again.
  func releaseDeepLink() { deepLinkAnchor = nil }

  func clearHighlight(_ anchor: String) {
    if highlight == anchor { highlight = nil }
  }
}

// MARK: - Anchors

private struct SettingsHighlightKey: EnvironmentKey {
  static let defaultValue: String? = nil
}

private struct SettingsRedundantTitleKey: EnvironmentKey {
  static let defaultValue: String? = nil
}

extension EnvironmentValues {
  /// A tool page's own title: sections named the same drop their header instead of repeating it.
  var settingsRedundantTitle: String? {
    get { self[SettingsRedundantTitleKey.self] }
    set { self[SettingsRedundantTitleKey.self] = newValue }
  }

  /// The anchor id Settings is pointing at, if any.
  var settingsHighlight: String? {
    get { self[SettingsHighlightKey.self] }
    set { self[SettingsHighlightKey.self] = newValue }
  }
}

extension View {
  /// Marks a row as a deep-link target: Settings scrolls to it and tints it briefly.
  func settingsAnchor(_ id: String) -> some View { modifier(SettingsAnchorModifier(id: id)) }
}

private struct SettingsAnchorModifier: ViewModifier {
  let id: String
  @Environment(\.settingsHighlight) private var highlight
  @State private var lit = false

  func body(content: Content) -> some View {
    content
      .id(id)
      .listRowBackground(lit ? Color.accentColor.opacity(0.22) : nil)
      .background {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
          .fill(Color.accentColor.opacity(lit ? 0.18 : 0))
          .padding(-6)
      }
      .onAppear { if highlight == id { flash() } }
      .onChange(of: highlight) { _, value in if value == id { flash() } }
  }

  private func flash() {
    withAnimation(.easeOut(duration: 0.25)) { lit = true }
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
      withAnimation(.easeInOut(duration: 0.6)) { lit = false }
    }
  }
}

// MARK: - Advanced

/// The rarely needed sections of a page, folded under one "Advanced" row so the page stays short.
/// It opens on its own when a deep link points at one of `anchors`.
struct SettingsAdvancedSections<Content: View>: View {
  var anchors: Set<String> = []
  @ViewBuilder let content: Content
  @EnvironmentObject private var navigator: SettingsNavigator
  @State private var expanded = false

  /// Open when the user opened it, or while a deep link points inside it.
  private var isExpanded: Bool { expanded || navigator.deepLinkAnchor.map(anchors.contains) == true }

  init(anchors: Set<String> = [], @ViewBuilder content: () -> Content) {
    self.anchors = anchors
    self.content = content()
  }

  @ViewBuilder var body: some View {
    Section {
      Button {
        let next = !isExpanded
        if !next { navigator.releaseDeepLink() }
        withAnimation(.easeInOut(duration: 0.2)) { expanded = next }
      } label: {
        HStack {
          Text(isExpanded ? "Hide Advanced Settings" : "Show Advanced Settings")
          Spacer()
          Image(systemName: "chevron.right")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .rotationEffect(.degrees(isExpanded ? 90 : 0))
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityAddTraits(.isButton)
      .accessibilityValue(isExpanded ? Text("Expanded") : Text("Collapsed"))
    }
    if isExpanded { content }
  }
}
