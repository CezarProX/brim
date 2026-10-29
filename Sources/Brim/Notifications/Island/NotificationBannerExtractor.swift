// NotificationBannerExtractor.swift
// Brim
//
// Turns the accessibility tree of a Notification Center banner into NotificationContent.
// The tree is first copied into plain `AXNodeSnapshot` values (bounded depth and size), so the
// extraction heuristics are pure and can be tested against a fake tree.

import Foundation

struct AXNodeSnapshot: Equatable {
  var role: String
  var subrole: String = ""
  var value: String = ""
  var title: String = ""
  var descriptionText: String = ""
  var children: [AXNodeSnapshot] = []
}

enum NotificationBannerExtractor {
  static let maxDepth = 9
  static let maxNodes = 160

  /// - Parameter isAppName: whether a string names an app (running or installed). Used to find the
  ///   app label inside the banner and to read it from the group's description.
  static func content(from root: AXNodeSnapshot, now: Date = Date(),
                      isAppName: (String) -> Bool) -> NotificationContent? {
    var texts: [String] = []
    var groupDescriptions: [String] = []
    var visited = 0
    collect(root, depth: 0, visited: &visited, texts: &texts, descriptions: &groupDescriptions)

    texts = texts.filter { !isNoise($0) }
    guard !texts.isEmpty else { return nil }

    var appName = groupDescriptions.compactMap { appCandidate(in: $0, isAppName: isAppName) }.first
    if let first = texts.first, isAppName(first), appName == nil || appName == first {
      appName = first
      texts.removeFirst()
    } else if let name = appName, texts.first == name {
      texts.removeFirst()
    }
    guard let app = appName else { return nil }

    // Remaining text order in the banner: title, [subtitle], body.
    var content = NotificationContent(appName: app, date: now)
    switch texts.count {
    case 0: return nil
    case 1: content.body = texts[0]
    case 2: content.title = texts[0]; content.body = texts[1]
    default:
      content.title = texts[0]
      content.subtitle = texts[1]
      content.body = texts.dropFirst(2).joined(separator: "\n")
    }
    return content
  }

  // MARK: Walk

  private static func collect(_ node: AXNodeSnapshot, depth: Int, visited: inout Int,
                              texts: inout [String], descriptions: inout [String]) {
    guard depth <= maxDepth, visited < maxNodes else { return }
    visited += 1
    switch node.role {
    case "AXStaticText":
      let text = firstNonEmpty(node.value, node.title, node.descriptionText)
      if !text.isEmpty { texts.append(text) }
    case "AXGroup":
      if !node.descriptionText.isEmpty { descriptions.append(node.descriptionText) }
    case "AXButton", "AXMenuButton", "AXPopUpButton":
      return  // action buttons ("Reply", "Close") are not content
    default: break
    }
    for child in node.children { collect(child, depth: depth + 1, visited: &visited, texts: &texts, descriptions: &descriptions) }
  }

  private static func firstNonEmpty(_ values: String...) -> String {
    values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty } ?? ""
  }

  /// Group descriptions look like "Messages, Anna, See you at 8" or just "Messages".
  private static func appCandidate(in description: String, isAppName: (String) -> Bool) -> String? {
    let head = description.split(separator: ",", maxSplits: 1).first.map(String.init)?
      .trimmingCharacters(in: .whitespaces) ?? ""
    return !head.isEmpty && isAppName(head) ? head : nil
  }

  /// Timestamps and button leftovers that show up as static text.
  static func isNoise(_ text: String) -> Bool {
    let lower = text.lowercased()
    if ["now", "close", "options", "clear", "reply", "show", "view", "snooze"].contains(lower) { return true }
    if lower.range(of: #"^\d+\s?(m|min|h|hr|d|s)( ago)?$"#, options: .regularExpression) != nil { return true }
    return false
  }
}
