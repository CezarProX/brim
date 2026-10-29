// WKWebPageDriver.swift
// Brim
//
// The real page: a WKWebView with its own persistent WKWebsiteDataStore (Brim-only, one per
// messenger), living in an off-screen keep-alive window so it never steals focus.
// Main-frame navigation is limited to the messenger's own site; pop-ups, downloads, camera and
// microphone requests are refused. Scripts run in an isolated content world.
// Verified in a standalone AppKit process: a fully off-screen window leaves the page "hidden"
// (no animation frames; Telegram Web renders nothing), the parked window keeps it "visible".

import AppKit
import WebKit

@MainActor
final class WKWebPageDriver: NSObject, WebPageDriving {
  let webView: WKWebView
  private let window: WebKeepAliveWindow
  private var screenWatch: NSObjectProtocol?
  private let dataStore: WKWebsiteDataStore
  private let allowedHosts: [String]

  /// - Parameter dataStore: tests pass a non-persistent store; the app uses the profile's own.
  init(profile: WebMessengerProfile, dataStore: WKWebsiteDataStore? = nil) {
    let store = dataStore ?? WKWebsiteDataStore(forIdentifier: profile.dataStoreID)
    let config = WKWebViewConfiguration()
    config.websiteDataStore = store
    config.mediaTypesRequiringUserActionForPlayback = .all
    if let source = profile.documentStart {
      config.userContentController.addUserScript(
        WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true, in: .page))
    }
    self.dataStore = store
    self.window = WebKeepAliveWindow(slot: profile.channel == .telegram ? 1 : 0)
    self.allowedHosts = Self.allowedHosts(for: profile.home)
    self.webView = WKWebView(frame: CGRect(origin: .zero, size: WebKeepAliveWindow.size), configuration: config)
    super.init()
    webView.customUserAgent = profile.userAgent
    webView.navigationDelegate = self
    webView.uiDelegate = self
    returnToKeepAlive()
    window.orderFrontRegardless()
    screenWatch = NotificationCenter.default.addObserver(
      forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.window.park() }
    }
  }

  var pageView: NSView? { webView }

  func load(_ url: URL) { webView.load(URLRequest(url: url)) }

  /// Test hook: loads a local fixture page.
  func loadHTML(_ html: String, baseURL: URL?) { webView.loadHTMLString(html, baseURL: baseURL) }

  func run(_ script: WebScript, arguments: [String: WebArgument]) async throws -> WebValue {
    let values = arguments.mapValues(\.javaScriptValue)
    let raw = try await webView.callAsyncJavaScript(script.source, arguments: values, in: nil, contentWorld: .defaultClient)
    return WebValue(raw)
  }

  func returnToKeepAlive() {
    guard let content = window.contentView, webView.superview !== content else { return }
    webView.removeFromSuperview()
    webView.frame = content.bounds
    webView.autoresizingMask = [.width, .height]
    content.addSubview(webView)
  }

  func eraseData() async {
    let types = WKWebsiteDataStore.allWebsiteDataTypes()
    await dataStore.removeData(ofTypes: types, modifiedSince: .distantPast)
  }

  func tearDown() {
    webView.stopLoading()
    webView.navigationDelegate = nil
    webView.uiDelegate = nil
    webView.removeFromSuperview()
    if let screenWatch { NotificationCenter.default.removeObserver(screenWatch) }
    screenWatch = nil
    window.orderOut(nil)
    window.close()
  }

  static func allowedHosts(for home: URL) -> [String] {
    guard let host = home.host?.lowercased() else { return [] }
    let parts = host.split(separator: ".")
    let site = parts.suffix(2).joined(separator: ".")
    return [host, site]
  }

  /// True when `url` stays on the messenger's own site (or is an internal blank/data page).
  static func isAllowed(_ url: URL?, hosts: [String]) -> Bool {
    guard let url else { return false }
    if ["about", "data", "blob"].contains(url.scheme?.lowercased() ?? "") { return true }
    guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else { return false }
    return hosts.contains { host == $0 || host.hasSuffix("." + $0) }
  }
}

extension WKWebPageDriver: WKNavigationDelegate, WKUIDelegate {
  func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
    guard navigationAction.targetFrame?.isMainFrame ?? true else { return .allow }
    return Self.isAllowed(navigationAction.request.url, hosts: allowedHosts) ? .allow : .cancel
  }

  func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
               for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? { nil }

  /// The reply pages never get the camera or microphone. (Swift's name for WebKit's
  /// `requestMediaCapturePermissionFor:…decisionHandler:`; a near-miss name is silently never called.)
  func webView(_ webView: WKWebView, decideMediaCapturePermissionsFor origin: WKSecurityOrigin,
               initiatedBy frame: WKFrameInfo, type: WKMediaCaptureType) async -> WKPermissionDecision { .deny }

  func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { webView.reload() }
}
