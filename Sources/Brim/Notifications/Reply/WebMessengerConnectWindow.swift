// WebMessengerConnectWindow.swift
// Brim
//
// A window that shows the hidden page itself. Linking normally happens in the inline QR panel;
// this is the fallback for steps the panel cannot show, such as Telegram's cloud password.
// When the page reports the chat list it says "Connected" and closes. Closing hands the page
// back to its parked window.

import AppKit
import Combine
import SwiftUI

@MainActor
final class WebMessengerConnectWindow: NSObject, NSWindowDelegate {
  private static var openWindows: [ReplyChannel: WebMessengerConnectWindow] = [:]

  private let window: NSWindow
  private let session: WebMessengerSession
  private var stateWatch: AnyCancellable?

  static func show(for session: WebMessengerSession) {
    session.activate()
    let controller = openWindows[session.profile.channel] ?? WebMessengerConnectWindow(session: session)
    openWindows[session.profile.channel] = controller
    NSApp.activate()
    controller.window.makeKeyAndOrderFront(nil)
  }

  private init(session: WebMessengerSession) {
    self.session = session
    window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 880, height: 720),
                      styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    super.init()
    window.title = WebMessengerText.connectTitle(session.profile.channel)
    window.isReleasedWhenClosed = false
    window.minSize = CGSize(width: 760, height: 620)
    window.contentView = NSHostingView(rootView: WebMessengerConnectView(session: session) { [weak self] in
      self?.window.close()
    })
    window.center()
    window.delegate = self
    watchForConnection()
  }

  /// Closes shortly after the page goes from "scan the code" to the chat list.
  private func watchForConnection() {
    var wasConnected = session.state == .connected
    stateWatch = session.$state.removeDuplicates().sink { [weak self] state in
      defer { wasConnected = state == .connected }
      guard state == .connected, !wasConnected else { return }
      Task { @MainActor [weak self] in
        try? await Task.sleep(for: .seconds(2))
        self?.window.close()
      }
    }
  }

  func windowWillClose(_ notification: Notification) {
    stateWatch = nil
    session.driver?.returnToKeepAlive()
    Self.openWindows[session.profile.channel] = nil
  }
}

private struct WebMessengerConnectView: View {
  @ObservedObject var session: WebMessengerSession
  var onDone: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      HStack(alignment: .center, spacing: 12) {
        VStack(alignment: .leading, spacing: 4) {
          Text(verbatim: WebMessengerText.instructions(session.profile.channel)).font(.callout)
          Text(verbatim: WebMessengerText.status(session.state, channel: session.profile.channel))
            .font(.caption).foregroundStyle(session.state == .connected ? .green : .secondary)
        }
        Spacer()
        Button("Done", action: onDone).keyboardShortcut(.defaultAction)
      }
      .padding(12)
      Divider()
      WebPageContainer(page: session.driver?.pageView)
    }
  }
}

/// Hosts the borrowed page view.
private struct WebPageContainer: NSViewRepresentable {
  let page: NSView?

  func makeNSView(context: Context) -> NSView {
    let host = NSView()
    attach(to: host)
    return host
  }

  func updateNSView(_ host: NSView, context: Context) { attach(to: host) }

  private func attach(to host: NSView) {
    guard let page, page.superview !== host else { return }
    page.removeFromSuperview()
    page.frame = host.bounds
    page.autoresizingMask = [.width, .height]
    host.addSubview(page)
  }
}
