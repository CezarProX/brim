// EditorTheme.swift
// Brim
//
// Design tokens for the "Edit screenshot" window: a dark, quiet surface so
// the screenshot and its background are the brightest things on screen.

import SwiftUI

enum EditorTheme {
    static let windowBackground = Color(red: 0.105, green: 0.105, blue: 0.115)
    static let sidebarBackground = Color(red: 0.125, green: 0.125, blue: 0.135)
    static let canvasBackground = Color(red: 0.075, green: 0.075, blue: 0.085)  // = EditorCanvasHostView.canvasBackground
    static let controlFill = Color.white.opacity(0.07)
    static let controlFillHover = Color.white.opacity(0.13)
    static let controlStroke = Color.white.opacity(0.09)
    static let separator = Color.white.opacity(0.08)
    static let primaryText = Color.white.opacity(0.92)
    static let secondaryText = Color.white.opacity(0.55)
    static let accent = Color.accentColor

    static let sidebarWidth: CGFloat = 276
    static let toolButtonSize: CGFloat = 30
    static let tileCorner: CGFloat = 10
    static let sectionSpacing: CGFloat = 22

    static let sectionTitle = Font.system(size: 12, weight: .semibold)
    static let rowTitle = Font.system(size: 13, weight: .medium)
    static let caption = Font.system(size: 11)
}

/// A sidebar section heading.
struct EditorSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(EditorTheme.sectionTitle)
            .foregroundStyle(EditorTheme.secondaryText)
            .textCase(nil)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Explanatory text under a control.
struct EditorCaption: View {
    let text: String

    var body: some View {
        Text(text)
            .font(EditorTheme.caption)
            .foregroundStyle(EditorTheme.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
