// SettingsFormComponents.swift
// Brim
//
// The shared pieces every Settings pane is built from, so the panes look like macOS System Settings:
// a hero header (icon, title, one line of description), grouped sections with small headers, rows
// with the control on the trailing edge, and explanations as secondary footnotes under a group.

import SwiftUI

/// A pane's content in a grouped Form, under the pane's hero header.
struct SettingsPage<Content: View>: View {
  let pane: SettingsPane
  @ViewBuilder let content: Content

  var body: some View {
    SettingsScrollingForm {
      SettingsPaneHeader(pane: pane)
      content
    }
  }
}

/// The grouped Form every Settings page uses. It scrolls to the row a deep link points at
/// (`SettingsNavigator.highlight`) and hands the highlight down so that row lights up.
struct SettingsScrollingForm<Content: View>: View {
  @ViewBuilder let content: Content
  @EnvironmentObject private var navigator: SettingsNavigator

  var body: some View {
    ScrollViewReader { proxy in
      Form { content }
        .formStyle(.grouped)
        // The window's glass shows through; the grouped sections float on it as frosted cards.
        .scrollContentBackground(.hidden)
        .toggleStyle(.switch)
        .environment(\.settingsHighlight, navigator.highlight)
        .onAppear { reveal(navigator.highlight, proxy) }
        .onChange(of: navigator.highlight) { _, anchor in reveal(anchor, proxy) }
    }
  }

  private func reveal(_ anchor: String?, _ proxy: ScrollViewProxy) {
    guard let anchor else { return }
    // Let an Advanced group open and the page lay out before scrolling.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
      withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo(anchor, anchor: .center) }
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { navigator.clearHighlight(anchor) }
  }
}

/// System Settings' top card: a picture of the feature, the page's name and what it is for.
struct SettingsPaneHeader: View {
  let pane: SettingsPane

  var body: some View {
    Section {
      VStack(spacing: 6) {
        SettingsHeroArt(pane: pane)
          .padding(.bottom, 6)
        Text(LocalizedStringKey(pane.rawValue))
          .font(.title3.weight(.semibold))
        Text(LocalizedStringKey(pane.summary))
          .font(.callout)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: 420)
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 8)
      .accessibilityElement(children: .combine)
      .accessibilityAddTraits(.isHeader)
    }
  }
}

/// A titled group of rows; `footer` is the explanation shown under the group in secondary text.
struct SettingsSection<Content: View>: View {
  let title: String?
  var footer: String?
  @ViewBuilder let content: Content

  init(_ title: String? = nil, footer: String? = nil, @ViewBuilder content: () -> Content) {
    self.title = title
    self.footer = footer
    self.content = content()
  }

  @Environment(\.settingsRedundantTitle) private var redundantTitle

  var body: some View {
    Section {
      content
    } header: {
      if let title, title != redundantTitle { Text(LocalizedStringKey(title)) }
    } footer: {
      if let footer { SettingsFootnote(footer) }
    }
  }
}

/// Secondary explanatory text, at footnote size, wrapping instead of truncating.
struct SettingsFootnote: View {
  let text: String

  init(_ text: String) { self.text = text }

  var body: some View {
    Text(LocalizedStringKey(text))
      .font(.footnote)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: .infinity, alignment: .leading)
  }
}

/// A row with a title (and optional subtitle) and a trailing push button, like System Settings'
/// "Software Update… [Update Now]" rows.
struct SettingsButtonRow: View {
  let title: String
  var subtitle: String?
  let button: String
  var role: ButtonRole?
  let action: () -> Void

  init(_ title: String, subtitle: String? = nil, button: String, role: ButtonRole? = nil, action: @escaping () -> Void) {
    self.title = title
    self.subtitle = subtitle
    self.button = button
    self.role = role
    self.action = action
  }

  var body: some View {
    LabeledContent {
      Button(LocalizedStringKey(button), role: role, action: action)
    } label: {
      Text(LocalizedStringKey(title))
      if let subtitle { Text(LocalizedStringKey(subtitle)) }
    }
  }
}
