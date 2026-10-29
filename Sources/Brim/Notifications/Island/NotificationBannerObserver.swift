// NotificationBannerObserver.swift
// Brim
//
// Watches the Notification Center process with an AXObserver. When a banner window or element
// appears it reads the banner's accessibility tree (bounded depth, short messaging timeout) and
// reports the content. Optionally presses the banner's Close action afterwards.
//
// Unverified against real banners in CI: macOS changes the banner's tree between releases, so the
// reader is deliberately heuristic. See NotificationBannerExtractor.

import AppKit
import ApplicationServices
import os

@MainActor
final class NotificationBannerObserver {
  static let log = Logger(subsystem: "io.github.cezarprox.brim", category: "notifications")
  var onContent: ((NotificationContent) -> Void)?
  var hidesBanner = false

  private var observer: AXObserver?
  private var appElement: AXUIElement?
  private var launchToken: NSObjectProtocol?
  private var pendingRead: DispatchWorkItem?

  static var isTrusted: Bool { AXIsProcessTrusted() }

  static func requestTrust() {
    let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
    _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
  }

  func start() {
    stop()
    attach()
    launchToken = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
    ) { [weak self] note in
      let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
      guard app?.bundleIdentifier == NotificationApps.notificationCenter else { return }
      Task { @MainActor in self?.attach() }
    }
  }

  func stop() {
    if let launchToken { NSWorkspace.shared.notificationCenter.removeObserver(launchToken) }
    launchToken = nil
    detach()
  }

  // MARK: Observer wiring

  private func attach() {
    detach()
    guard Self.isTrusted,
      let app = NSRunningApplication.runningApplications(withBundleIdentifier: NotificationApps.notificationCenter).first
    else {
      Self.log.error("attach skipped: trusted=\(Self.isTrusted, privacy: .public)")
      return
    }
    var created: AXObserver?
    let callback: AXObserverCallback = { _, element, _, refcon in
      guard let refcon else { return }
      let me = Unmanaged<NotificationBannerObserver>.fromOpaque(refcon).takeUnretainedValue()
      Task { @MainActor in me.bannerAppeared(element) }
    }
    let createResult = AXObserverCreate(app.processIdentifier, callback, &created)
    guard createResult == .success, let created else {
      Self.log.error("AXObserverCreate failed: \(createResult.rawValue, privacy: .public)")
      return
    }
    let element = AXUIElementCreateApplication(app.processIdentifier)
    AXUIElementSetMessagingTimeout(element, 0.3)
    let refcon = Unmanaged.passUnretained(self).toOpaque()
    for name in [kAXWindowCreatedNotification, kAXCreatedNotification] {
      let result = AXObserverAddNotification(created, element, name as CFString, refcon)
      if result != .success { Self.log.error("observe \(name, privacy: .public) failed: \(result.rawValue, privacy: .public)") }
    }
    CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
    observer = created
    appElement = element
  }

  private func detach() {
    pendingRead?.cancel()
    if let observer { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes) }
    observer = nil
    appElement = nil
  }

  // MARK: Reading

  private func bannerAppeared(_ element: AXUIElement) {
    // The banner's text is filled in a beat after the window exists. Coalesce bursts of events.
    pendingRead?.cancel()
    let work = DispatchWorkItem { [weak self] in self?.read(from: element) }
    pendingRead = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
  }

  private func read(from element: AXUIElement) {
    AXUIElementSetMessagingTimeout(element, 0.3)
    let root = Self.window(containing: element) ?? element
    var budget = NotificationBannerExtractor.maxNodes
    let snapshot = Self.snapshot(root, depth: 0, budget: &budget)
    let resolver = NotificationAppResolver.shared
    guard var content = NotificationBannerExtractor.content(from: snapshot, isAppName: { resolver.isAppName($0) }) else { return }
    content.bundleID = resolver.bundleID(forName: content.appName)
    onContent?(content)
    if hidesBanner { Self.pressClose(in: root) }
  }

  private static func window(containing element: AXUIElement) -> AXUIElement? {
    var current = element
    for _ in 0..<8 {
      if string(current, kAXRoleAttribute) == kAXWindowRole as String { return current }
      var parent: CFTypeRef?
      guard AXUIElementCopyAttributeValue(current, kAXParentAttribute as CFString, &parent) == .success,
        let parent, CFGetTypeID(parent) == AXUIElementGetTypeID()
      else { return nil }
      current = parent as! AXUIElement  // swiftlint:disable:this force_cast
    }
    return nil
  }

  static func snapshot(_ element: AXUIElement, depth: Int, budget: inout Int) -> AXNodeSnapshot {
    budget -= 1
    var node = AXNodeSnapshot(role: string(element, kAXRoleAttribute) ?? "")
    node.subrole = string(element, kAXSubroleAttribute) ?? ""
    node.value = string(element, kAXValueAttribute) ?? ""
    node.title = string(element, kAXTitleAttribute) ?? ""
    node.descriptionText = string(element, kAXDescriptionAttribute) ?? ""
    guard depth < NotificationBannerExtractor.maxDepth, budget > 0 else { return node }
    var children: CFTypeRef?
    if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
      let list = children as? [AXUIElement] {
      for child in list where budget > 0 { node.children.append(snapshot(child, depth: depth + 1, budget: &budget)) }
    }
    return node
  }

  private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
    return value as? String
  }

  // MARK: Hiding

  /// Best effort: finds a descendant exposing a "Close" action and performs it.
  private static func pressClose(in root: AXUIElement) {
    var budget = 80
    func visit(_ element: AXUIElement, depth: Int) -> Bool {
      budget -= 1
      var names: CFArray?
      if AXUIElementCopyActionNames(element, &names) == .success,
        let list = names as? [String], list.contains(where: { $0.localizedCaseInsensitiveContains("Close") }) {
        let action = list.first { $0.localizedCaseInsensitiveContains("Close") }!
        return AXUIElementPerformAction(element, action as CFString) == .success
      }
      guard depth < 6, budget > 0 else { return false }
      var children: CFTypeRef?
      guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
        let list = children as? [AXUIElement] else { return false }
      return list.contains { visit($0, depth: depth + 1) }
    }
    _ = visit(root, depth: 0)
  }
}
