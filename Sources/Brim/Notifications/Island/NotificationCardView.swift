// NotificationCardView.swift
// Brim
//
// The island's notification surfaces. `NotificationCompactView` sits on the wings (app icon on
// the left, sender on the right); `NotificationCardView` is the expanded card with body, time,
// dismiss, "+N" queue badge and, for Messages, WhatsApp and Telegram, an inline reply bar.

import AppKit
import SwiftUI

/// Icon for a notification: the app's real icon, or a tinted initial when the app is unknown.
struct NotificationAppIcon: View {
  let content: NotificationContent
  var size: CGFloat = 40

  var body: some View {
    Group {
      if let image = NotificationAppResolver.shared.icon(forBundleID: content.bundleID) {
        Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
      } else {
        RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
          .fill(fallbackColor.gradient)
          .overlay(Text(String(content.appName.prefix(1)).uppercased())
            .font(.system(size: size * 0.46, weight: .bold, design: .rounded)).foregroundStyle(.white))
      }
    }
    .frame(width: size, height: size)
    .accessibilityHidden(true)
  }

  private var fallbackColor: Color {
    let hue = Double(abs(content.appName.hashValue % 360)) / 360
    return Color(hue: hue, saturation: 0.55, brightness: 0.85)
  }
}

// MARK: - Compact

/// The closed island's notification: on a notch the app icon is centred in the left wing and the
/// sender in the right one (nothing under the camera); on the pill (`notchWidth == 0`) icon and
/// sender form one centred group. Laid out by `CompactLayout`, like every other compact row.
struct NotificationCompactView: View {
  let content: NotificationContent
  var overflow = 0
  /// Width of the camera housing between the two wings; 0 on the pill.
  var notchWidth: CGFloat = 0
  /// Each wing's width beside the housing (notch only).
  var wing: CGFloat = 0
  /// How far the notch shape's side edges sit inside the wings' frame.
  var shoulder: CGFloat = 0

  private static let badgeGap: CGFloat = 6

  static func sender(_ content: NotificationContent) -> String {
    content.title.isEmpty ? content.appName : content.title
  }

  /// Width of the sender plus the "+N" badge; the island is sized from it.
  static func labelWidth(_ content: NotificationContent, overflow: Int, floating: Bool) -> CGFloat {
    let limit = floating ? CompactLayout.pillLabelLimit : CompactLayout.notchLabelLimit
    return CompactLayout.labelWidth(sender(content), limit: limit)
      + (overflow > 0 ? badgeGap + badgeWidth(overflow) : 0)
  }

  /// An upper bound for the badge: its caption text measured at label size, plus its padding.
  static func badgeWidth(_ count: Int) -> CGFloat { 12 + CompactLayout.labelWidth("+\(count)", limit: 40) }

  var body: some View {
    Group {
      if notchWidth > 0 {
        CompactWingsRow(leftWing: wing, rightWing: wing, notchWidth: notchWidth, shoulder: shoulder) {
          icon
        } trailing: {
          label
        }
      } else {
        CompactGroupRow { icon } trailing: { label }
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(content.appName) notification from \(content.title)")
  }

  private var icon: some View { NotificationAppIcon(content: content, size: 22) }

  private var label: some View {
    HStack(spacing: Self.badgeGap) {
      Text(Self.sender(content))
        .font(CompactLayout.labelFont).foregroundStyle(IslandInk.primary)
        .lineLimit(1).truncationMode(.tail).minimumScaleFactor(CompactLayout.labelMinimumScale)
      if overflow > 0 { NotificationOverflowBadge(count: overflow).fixedSize() }
    }
    .frame(width: Self.labelWidth(content, overflow: overflow, floating: notchWidth == 0))
  }
}

struct NotificationOverflowBadge: View {
  let count: Int
  var body: some View {
    Text("+\(count)")
      .font(IslandFont.caption.monospacedDigit()).foregroundStyle(IslandInk.primary)
      .padding(.horizontal, 6).frame(height: 18)
      .background(IslandFill.selected, in: Capsule())
      .contentTransition(.numericText())
  }
}

// MARK: - Expanded card

struct NotificationCardView: View {
  let content: NotificationContent
  var overflow = 0
  var replyState: NotificationHUDModel.ReplyState = .idle
  var now = Date()
  var onOpen: () -> Void = {}
  var onDismiss: () -> Void = {}
  var onReply: (String) -> Void = { _ in }
  var onHoldChange: (Bool) -> Void = { _ in }
  /// The reply field's text, kept by the model so it survives the link panel.
  var draft: Binding<String> = .constant("")
  /// Non-nil while the inline "Link WhatsApp to reply" panel replaces the reply bar.
  var linkPhase: LinkPhase?
  var link = NotificationLinkActions()

  @State private var hovered = false
  @State private var dragY: CGFloat = 0
  @State private var replyFocused = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    VStack(alignment: .leading, spacing: IslandSpace.m) {
      HStack(alignment: .top, spacing: IslandSpace.m) {
        NotificationAppIcon(content: content, size: 40)
        textColumn
        trailing
      }
      if content.supportsReply, let channel = content.replyChannel {
        if let linkPhase {
          ReplyLinkPanel(
            channel: channel, phase: linkPhase, hasDraft: !draft.wrappedValue.isEmpty, onClose: link.cancel,
            onRetry: link.retry, onOpenPage: link.openPage)
          .contentShape(Rectangle())
          .onTapGesture {}
          .transition(.islandContent)
        } else {
          NotificationReplyBar(channel: channel, text: draft, replyState: replyState, onSend: onReply) { focused in
            replyFocused = focused
            if focused { link.fieldFocused() }
            onHoldChange(focused || hovered)
          }
          .transition(.islandContent)
        }
      }
    }
    .animation(NotchMotion.layout(reduceMotion: reduceMotion), value: linkPhase == nil)
    .padding(IslandSpace.m)
    .frame(width: 372, alignment: .leading)
    .contentShape(Rectangle())
    .offset(y: min(0, dragY))
    .opacity(1 - min(0.6, Double(-min(0, dragY)) / 80))
    .onHover { inside in
      hovered = inside
      onHoldChange(inside || replyFocused)
    }
    .onTapGesture(perform: onOpen)
    .gesture(swipeUp, including: linkPhase == nil ? .all : .subviews)
    .animation(NotchMotion.feedback(reduceMotion: reduceMotion), value: hovered)
    .accessibilityElement(children: .contain)
    .accessibilityAction(named: "Dismiss", onDismiss)
  }

  private var textColumn: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(content.appName.uppercased())
        .font(IslandFont.caption).tracking(0.6).foregroundStyle(IslandInk.tertiary).lineLimit(1)
      if !content.title.isEmpty {
        Text(content.title).font(IslandFont.headline).foregroundStyle(IslandInk.primary).lineLimit(1)
      }
      if !content.subtitle.isEmpty {
        Text(content.subtitle).font(IslandFont.label).foregroundStyle(IslandInk.secondary).lineLimit(1)
      }
      if !content.body.isEmpty {
        Text(content.body).font(IslandFont.body).foregroundStyle(IslandInk.secondary)
          .lineLimit(2).fixedSize(horizontal: false, vertical: true)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var trailing: some View {
    VStack(alignment: .trailing, spacing: IslandSpace.s) {
      ZStack(alignment: .topTrailing) {
        Text(NotificationTimeLabel.text(for: content.date, now: now))
          .font(IslandFont.caption).foregroundStyle(IslandInk.tertiary).opacity(hovered ? 0 : 1)
        Button(action: onDismiss) {
          Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(IslandInk.primary)
            .frame(width: 20, height: 20).background(IslandFill.raised, in: Circle())
        }
        .buttonStyle(IslandPressStyle())
        .opacity(hovered ? 1 : 0)
        .accessibilityLabel("Dismiss notification")
      }
      if overflow > 0 { NotificationOverflowBadge(count: overflow) }
    }
  }

  private var swipeUp: some Gesture {
    DragGesture(minimumDistance: 6)
      .onChanged { dragY = $0.translation.height }
      .onEnded { value in
        if value.translation.height < -28 || value.predictedEndTranslation.height < -70 { onDismiss() }
        withAnimation(NotchMotion.layout(reduceMotion: reduceMotion)) { dragY = 0 }
      }
  }
}

/// What the link panel inside a card can ask for.
struct NotificationLinkActions {
  var cancel: () -> Void = {}
  var retry: () -> Void = {}
  var openPage: () -> Void = {}
  var fieldFocused: () -> Void = {}
}

/// Heights of the open card below the notch.
enum NotificationCardMetrics {
  static let plain: CGFloat = 92
  static let withReply: CGFloat = 136
  /// The link panel takes the reply bar's place (32 pt) and its own height.
  static let linking: CGFloat = withReply - 32 + ReplyLinkPanel.height

  static func bodyHeight(supportsReply: Bool, linking isLinking: Bool) -> CGFloat {
    guard supportsReply else { return plain }
    return isLinking ? linking : withReply
  }
}

// MARK: - Host bound to the shared model

/// What the shell embeds: the expanded card for the current notification, if any.
struct NotificationHUDHost: View {
  @ObservedObject var model: NotificationHUDModel = .shared

  var body: some View {
    if let item = model.current {
      Group {
        if let linker = model.replies.linker, model.replies.linkingItemID == item.id {
          LinkerPhaseReader(linker: linker) { card(item, phase: $0, linker: linker) }
        } else {
          card(item, phase: nil, linker: nil)
        }
      }
      .id(item.id)
      .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
    }
  }

  private func card(_ item: NotificationContent, phase: LinkPhase?, linker: ReplyLinker?) -> NotificationCardView {
    let replies = model.replies
    let draft = Binding(get: { replies.drafts[item.id] ?? "" }, set: { replies.drafts[item.id] = $0 })
    let actions = NotificationLinkActions(
      cancel: { replies.cancelLink() }, retry: { linker?.retry() },
      openPage: {
        if let session = linker?.session as? WebMessengerSession { WebMessengerConnectWindow.show(for: session) }
      },
      fieldFocused: { model.replyFieldFocused(item) })
    return NotificationCardView(
      content: item, overflow: model.overflow, replyState: model.replyState,
      onOpen: { model.open(item) }, onDismiss: { model.dismiss() },
      onReply: { model.reply($0, to: item) }, onHoldChange: { model.setPaused($0) },
      draft: draft, linkPhase: phase, link: actions)
  }
}

/// Re-renders its content whenever the linker's phase changes.
private struct LinkerPhaseReader<Content: View>: View {
  @ObservedObject var linker: ReplyLinker
  let content: (LinkPhase) -> Content

  var body: some View { content(linker.phase) }
}
