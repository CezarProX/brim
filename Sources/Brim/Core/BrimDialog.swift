// BrimDialog.swift
// Brim
//
// A native-feeling confirmation panel for decisions that deserve more than a bare NSAlert: the app
// icon, a plain-language title, a few bullets saying what will happen, an optional "Show details"
// disclosure (for exact technical text such as JSON) and Cancel / confirm buttons. It runs modally
// and returns which button was pressed; callers only act after it returns true.

import AppKit
import SwiftUI

/// Everything a dialog shows. Strings arrive already localized.
struct BrimDialogContent {
  struct Point: Hashable {
    let symbol: String
    let text: String
  }

  var title: String
  var message: String?
  var points: [Point] = []
  /// Exact technical text behind a "Show details" disclosure, shown in a monospaced scroll box.
  var details: String?
  var confirmTitle: String = L10n.tr("OK")
  /// nil for a single-button notice.
  var cancelTitle: String? = L10n.tr("Cancel")
  var isDestructive = false
}

struct BrimDialogView: View {
  let content: BrimDialogContent
  var icon: NSImage = AppIconRenderer.image(for: AppSettings.shared.appIconVariant, size: 64)
  var detailsInitiallyShown = false
  let onFinish: (Bool) -> Void

  @State private var showsDetails = false

  static let width: CGFloat = 460

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      header
      if !content.points.isEmpty { points }
      if let details = content.details { detailsBox(details) }
      buttons
    }
    .padding(.horizontal, 22)
    .padding(.top, 22)
    .padding(.bottom, 18)
    .frame(width: Self.width, alignment: .leading)
    .onAppear { showsDetails = detailsInitiallyShown }
    // Frosted glass like every other Brim window (`GlassStyle`), solid under Reduce Transparency.
    .background { GlassWindowBackdrop().ignoresSafeArea() }
  }

  private var header: some View {
    HStack(alignment: .top, spacing: 14) {
      Image(nsImage: icon).resizable().frame(width: 56, height: 56).accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 4) {
        Text(verbatim: content.title)
          .font(.system(size: 15, weight: .semibold))
          .fixedSize(horizontal: false, vertical: true)
        if let message = content.message {
          Text(verbatim: message)
            .font(.system(size: 12.5)).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .padding(.top, 4)
    }
  }

  private var points: some View {
    VStack(alignment: .leading, spacing: 10) {
      ForEach(content.points, id: \.self) { point in
        HStack(alignment: .firstTextBaseline, spacing: 10) {
          Image(systemName: point.symbol)
            .font(.system(size: 13, weight: .medium)).foregroundStyle(Color.accentColor)
            .frame(width: 18).accessibilityHidden(true)
          Text(verbatim: point.text)
            .font(.system(size: 12.5))
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))
  }

  private func detailsBox(_ details: String) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Button {
        withAnimation(.easeInOut(duration: 0.18)) { showsDetails.toggle() }
      } label: {
        HStack(spacing: 5) {
          Image(systemName: "chevron.right")
            .font(.system(size: 10, weight: .semibold))
            .rotationEffect(.degrees(showsDetails ? 90 : 0))
          Text(verbatim: showsDetails ? L10n.tr("Hide details") : L10n.tr("Show details"))
            .font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(.secondary)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      if showsDetails {
        ScrollView([.vertical, .horizontal]) {
          Text(verbatim: details)
            .font(.system(size: 11, design: .monospaced))
            .textSelection(.enabled)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 170)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(nsColor: .textBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
      }
    }
  }

  private var buttons: some View {
    HStack(spacing: 10) {
      Spacer()
      if let cancel = content.cancelTitle {
        Button { onFinish(false) } label: { Text(verbatim: cancel).frame(minWidth: 72) }
          .keyboardShortcut(.cancelAction)
          .controlSize(.large)
      }
      Button(role: content.isDestructive ? .destructive : nil) { onFinish(true) } label: {
        Text(verbatim: content.confirmTitle).frame(minWidth: 72)
      }
      .keyboardShortcut(.defaultAction)
      .buttonStyle(.borderedProminent)
      .controlSize(.large)
    }
    .padding(.top, 2)
  }
}

/// Shows a `BrimDialogContent` as an app-modal panel.
@MainActor
enum BrimDialog {
  /// Returns true when the confirm button was pressed (Return), false for Cancel, Escape or closing.
  @discardableResult
  static func run(_ content: BrimDialogContent) -> Bool {
    var confirmed = false
    let panel = BrimDialogPanel(contentRect: .zero, styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
    let view = BrimDialogView(content: content) { result in
      confirmed = result
      NSApp.stopModal()
    }
    // The controller resizes the panel as "Show details" opens and closes.
    let host = BrimDialogHostingController(rootView: view)
    host.sizingOptions = [.preferredContentSize]
    panel.contentViewController = host
    panel.becomesKeyOnlyIfNeeded = false
    panel.setContentSize(host.view.fittingSize)
    panel.title = content.title
    panel.titleVisibility = .hidden
    panel.titlebarAppearsTransparent = true
    GlassWindowChrome.apply(to: panel)
    panel.isMovableByWindowBackground = true
    panel.isReleasedWhenClosed = false
    panel.level = .modalPanel
    panel.animationBehavior = .alertPanel
    for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
      panel.standardWindowButton(button)?.isHidden = true
    }
    panel.center()
    NSApp.activate(ignoringOtherApps: true)
    panel.makeKeyAndOrderFront(nil)
    NSApp.runModal(for: panel)
    panel.orderOut(nil)
    return confirmed
  }
}

/// Always able to become key: Brim runs as an accessory app, and a dialog that can't take key
/// leaves its buttons waiting for a click that only activates the window.
private final class BrimDialogPanel: NSPanel {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }
}

/// Buttons answer the first click even if the dialog isn't key yet.
private final class BrimDialogHostingController<Content: View>: NSHostingController<Content> {
  override func loadView() {
    view = FirstClickHostingView(rootView: rootView)
  }
}
