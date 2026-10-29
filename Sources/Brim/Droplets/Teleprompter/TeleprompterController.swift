// TeleprompterController.swift
// Brim
//
// The always-on-top prompter that sits right under the camera, above fullscreen apps while active.

import AppKit
import SwiftUI

private final class PrompterPanel: NSPanel {
  override var canBecomeKey: Bool { true }
  override func cancelOperation(_ sender: Any?) { TeleprompterController.shared.hidePrompter() }
}

@MainActor
final class TeleprompterController {
  static let shared = TeleprompterController()
  private var panel: NSPanel?
  private let settings = AppSettings.shared
  private let model = TeleprompterModel.shared
  private init() {}

  var isVisible: Bool { panel?.isVisible ?? false }

  func start() {
    stop()
    guard settings.teleprompterEnabled else { return }
    DropletHotkeyCenter.shared.register(.teleprompter, shortcut: settings.teleprompterShortcut) { [weak self] in
      guard let self else { return }
      self.isVisible ? self.hidePrompter() : self.showPrompter(autoPlay: false)
    }
  }

  func stop() {
    DropletHotkeyCenter.shared.unregister(.teleprompter)
    hidePrompter()
  }

  func settingsChanged() {
    if settings.teleprompterEnabled { start() } else { stop() }
    panel?.sharingType = settings.teleprompterHiddenFromCapture ? .none : .readOnly
  }

  /// Frame centered under the camera: below the notch on a notched Mac, otherwise at the top edge.
  static func frame(on screen: NSScreen, size: CGSize = CGSize(width: 380, height: 150)) -> CGRect {
    let topInset = screen.safeAreaInsets.top
    return CGRect(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - topInset - size.height - 2,
                  width: size.width, height: size.height)
  }

  func showPrompter(autoPlay: Bool) {
    let panel = self.panel ?? makePanel()
    self.panel = panel
    let screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens[0]
    panel.setFrame(Self.frame(on: screen), display: true)
    panel.sharingType = settings.teleprompterHiddenFromCapture ? .none : .readOnly
    panel.alphaValue = 0
    panel.makeKeyAndOrderFront(nil)
    NSAnimationContext.runAnimationGroup { context in
      context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.2
      panel.animator().alphaValue = 1
    }
    if autoPlay { model.play() }
  }

  func hidePrompter() {
    model.pause()
    guard let panel, panel.isVisible else { return }
    NSAnimationContext.runAnimationGroup({ context in
      context.duration = 0.15
      panel.animator().alphaValue = 0
    }, completionHandler: { panel.orderOut(nil) })
  }

  private func makePanel() -> NSPanel {
    let panel = PrompterPanel(
      contentRect: CGRect(x: 0, y: 0, width: 380, height: 150),
      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
    panel.isReleasedWhenClosed = false
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    // Above fullscreen apps and the menu bar, on every Space, only while the panel is shown.
    panel.level = .statusBar
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    panel.hidesOnDeactivate = false
    let root = PrompterPanelView().preferredColorScheme(.dark)
    panel.contentView = NSHostingView(rootView: root)
    return panel
  }
}

private struct PrompterPanelView: View {
  @ObservedObject private var model = TeleprompterModel.shared

  var body: some View {
    VStack(spacing: 4) {
      TeleprompterScrollView(model: model)
        .overlay(alignment: .topTrailing) {
          Button { TeleprompterController.shared.hidePrompter() } label: {
            Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(IslandInk.secondary)
              .frame(width: 28, height: 28).contentShape(Rectangle())
          }
          .buttonStyle(.plain).help("Close the prompter (Esc)").accessibilityLabel("Close the prompter")
        }
      TeleprompterControls(model: model).padding(.horizontal, 10).padding(.bottom, 8)
    }
    .background(Color.black, in: UnevenRoundedRectangle(bottomLeadingRadius: IslandRadius.large, bottomTrailingRadius: IslandRadius.large, style: .continuous))
    .overlay {
      UnevenRoundedRectangle(bottomLeadingRadius: IslandRadius.large, bottomTrailingRadius: IslandRadius.large, style: .continuous)
        .strokeBorder(IslandFill.hairline)
    }
  }
}
