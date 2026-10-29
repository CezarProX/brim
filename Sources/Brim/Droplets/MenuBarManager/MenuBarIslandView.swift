import AppKit
import SwiftUI

/// Menu Bar Manager inside the island: turn it on, see what it does, hide and show the icons.
@MainActor
struct MenuBarIslandView: View {
  @ObservedObject private var manager = MenuBarManagerController.shared
  @State private var autoRehide = AppSettings.shared.menuBarManagerAutoRehide
  @State private var seconds = AppSettings.shared.menuBarManagerRehideSeconds
  @State private var startCollapsed = AppSettings.shared.menuBarManagerStartCollapsed
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  /// Fixed state for renders and tests; nil follows the real manager.
  var previewRunning: Bool?
  var previewCollapsed: Bool?
  var previewNotice: String?

  private var running: Bool { previewRunning ?? manager.isRunning }
  private var collapsed: Bool { previewCollapsed ?? manager.isCollapsed }
  private var notice: String? { previewNotice ?? manager.lastNotice }

  var body: some View {
    Group {
      if running { controls } else { intro }
    }
    .animation(reduceMotion ? nil : .snappy(duration: 0.22), value: running)
  }

  private var intro: some View {
    IslandIntroCard(
      symbol: "menubar.rectangle", tint: Color(red: 0.25, green: 0.6, blue: 1),
      headline: L10n.tr("Tuck menu bar icons behind one arrow"),
      lines: [
        ("arrow.left.and.right", L10n.tr("Adds a divider and an arrow to your menu bar")),
        ("command", L10n.tr("Hold ⌘ and drag icons to the left of the divider")),
        ("chevron.right", L10n.tr("Click the arrow to hide or show them")),
      ],
      actionTitle: L10n.tr("Turn on"), action: { manager.enable() },
      footnote: L10n.tr("Only icons left of the divider are hidden."))
  }

  private var controls: some View {
    VStack(alignment: .leading, spacing: 10) {
      MenuBarDiagram(collapsed: collapsed)
        .frame(height: 46)
      HStack(spacing: 12) {
        VStack(alignment: .leading, spacing: 1) {
          Text(collapsed ? L10n.tr("Icons are hidden") : L10n.tr("Icons are showing"))
            .font(.system(size: 13.5, weight: .semibold)).foregroundStyle(IslandInk.primary)
          Text(collapsed ? L10n.tr("Click the arrow in the menu bar, or the button, to bring them back.") : L10n.tr("Icons left of the divider tuck away when you hide."))
            .font(.system(size: 12)).foregroundStyle(IslandInk.secondary).lineLimit(2)
        }
        Spacer(minLength: 6)
        Button { manager.setCollapsed(!manager.isCollapsed) } label: {
          Text(collapsed ? L10n.tr("Show icons") : L10n.tr("Hide icons"))
        }
        .buttonStyle(IslandPillStyle(prominent: true, tint: Color(red: 0.25, green: 0.6, blue: 1)))
      }
      if let notice {
        Label(notice, systemImage: "hand.point.up.left.fill").font(.system(size: 12.5, weight: .medium))
          .foregroundStyle(Color.orange).padding(.horizontal, 10).padding(.vertical, 6)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
      }
      HStack(spacing: 16) {
        Toggle("Hide again after", isOn: $autoRehide)
          .onChange(of: autoRehide) { _, v in AppSettings.shared.menuBarManagerAutoRehide = v; manager.setCollapsed(manager.isCollapsed) }
        if autoRehide {
          Stepper(value: $seconds, in: 2...60) { Text(L10n.tr("%lld s", seconds)).monospacedDigit() }
            .onChange(of: seconds) { _, v in AppSettings.shared.menuBarManagerRehideSeconds = v }
        }
        Spacer(minLength: 0)
        Toggle("Hide at launch", isOn: $startCollapsed)
          .onChange(of: startCollapsed) { _, v in AppSettings.shared.menuBarManagerStartCollapsed = v }
      }
      .toggleStyle(.switch).controlSize(.small).font(.system(size: 12.5)).foregroundStyle(IslandInk.secondary)
      Spacer(minLength: 0)
      HStack(alignment: .top, spacing: 8) {
        Text("macOS can't move other apps' icons for you, so you place them with ⌘-drag. On a Mac with a notch, macOS may also hide icons on its own when the bar is full.")
          .font(.system(size: 11.5)).foregroundStyle(IslandInk.tertiary).fixedSize(horizontal: false, vertical: true)
        Button("Turn off") { manager.disable() }.buttonStyle(IslandPillStyle(compact: true))
      }
    }
  }
}

/// A tiny drawing of the menu bar: hidden icons, the divider, the arrow, the icons that stay.
private struct MenuBarDiagram: View {
  let collapsed: Bool

  var body: some View {
    HStack(spacing: 10) {
      Spacer(minLength: 0)
      HStack(spacing: 6) {
        ForEach(0..<3, id: \.self) { _ in icon.opacity(collapsed ? 0 : 0.7) }
      }
      .overlay(alignment: .trailing) {
        if collapsed { Text("hidden").font(.system(size: 11)).foregroundStyle(IslandInk.tertiary) }
      }
      Rectangle().fill(IslandInk.secondary).frame(width: 1.5, height: 18)
      Image(systemName: collapsed ? "chevron.left" : "chevron.right").font(.system(size: 12, weight: .bold))
        .foregroundStyle(IslandInk.primary)
      HStack(spacing: 6) {
        icon; icon
        Image(systemName: "clock").font(.system(size: 12)).foregroundStyle(IslandInk.secondary)
      }
    }
    .padding(.horizontal, 14)
    .background(IslandFill.subtle, in: Capsule())
    .overlay { Capsule().strokeBorder(IslandFill.hairline, lineWidth: 0.75) }
    .accessibilityHidden(true)
  }

  private var icon: some View {
    RoundedRectangle(cornerRadius: 4, style: .continuous).fill(IslandInk.secondary).frame(width: 16, height: 14)
  }
}
