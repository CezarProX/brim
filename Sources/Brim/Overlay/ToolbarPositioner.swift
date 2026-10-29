// ToolbarPositioner.swift
// Brim
//
// Computes floating on-screen frames for the edit toolbar and action bar
// hosted alongside an active selection.
//
// Layout policy:
//  - The toolbar is placed to the right of the selection by default; if
//    there isn't enough room, it moves to the left instead.
//  - The action bar is placed directly below the toolbar; if there isn't
//    enough room below, it moves above instead.
//  - Both frames are then clamped fully inside `screenBounds` (with
//    `margin`) — staying fully on-screen takes priority over the
//    right/below placement preference.

import CoreGraphics

enum ToolbarPositioner {

    static let gap: CGFloat = 12
    static let margin: CGFloat = 16

    struct Layout {
        var toolbar: CGRect
        var actionBar: CGRect
    }

    static func layout(selection: CGRect, screenBounds: CGRect, toolbarSize: CGSize, actionBarSize: CGSize) -> Layout {
        let toolbarX = toolbarXPosition(selection: selection, screenBounds: screenBounds, width: toolbarSize.width)
        let toolbarTopY = selection.maxY
        let toolbarFrame = clampFully(
            CGRect(x: toolbarX, y: toolbarTopY - toolbarSize.height, width: toolbarSize.width, height: toolbarSize.height),
            in: screenBounds
        )

        let actionBarX = toolbarFrame.midX - actionBarSize.width / 2
        let belowY = toolbarFrame.minY - gap - actionBarSize.height
        let actionBarY: CGFloat = belowY >= screenBounds.minY + margin
            ? belowY
            : toolbarFrame.maxY + gap
        let actionBarFrame = clampFully(
            CGRect(x: actionBarX, y: actionBarY, width: actionBarSize.width, height: actionBarSize.height),
            in: screenBounds
        )

        return Layout(toolbar: toolbarFrame, actionBar: actionBarFrame)
    }

    private static func toolbarXPosition(selection: CGRect, screenBounds: CGRect, width: CGFloat) -> CGFloat {
        let rightX = selection.maxX + gap
        if rightX + width + margin <= screenBounds.maxX {
            return rightX
        }
        let leftX = selection.minX - gap - width
        if leftX - margin >= screenBounds.minX {
            return leftX
        }
        // Neither side fully fits — prefer the right position; the final
        // `clampFully` pass pulls it back fully on-screen.
        return rightX
    }

    private static func clampFully(_ rect: CGRect, in bounds: CGRect) -> CGRect {
        var r = rect
        if r.width > bounds.width { r.size.width = bounds.width }
        if r.height > bounds.height { r.size.height = bounds.height }
        if r.minX < bounds.minX + margin { r.origin.x = bounds.minX + margin }
        if r.minY < bounds.minY + margin { r.origin.y = bounds.minY + margin }
        if r.maxX > bounds.maxX - margin { r.origin.x = bounds.maxX - margin - r.width }
        if r.maxY > bounds.maxY - margin { r.origin.y = bounds.maxY - margin - r.height }
        return r
    }
}
