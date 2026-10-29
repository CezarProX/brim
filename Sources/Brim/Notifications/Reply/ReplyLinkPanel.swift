// ReplyLinkPanel.swift
// Brim
//
// The inline "Link WhatsApp to reply" panel: the live QR code on a white tile, three steps with
// the phone app's real menu path, and a privacy line. The same view sits in the island card, in
// Settings and on the onboarding page. Phases: getting code, code, linking, success, failed.

import AppKit
import SwiftUI

struct ReplyLinkPanel: View {
  let channel: ReplyChannel
  let phase: LinkPhase
  /// When set, a reply is waiting to go out after linking.
  var hasDraft = false
  var onClose: (() -> Void)?
  var onRetry: () -> Void = {}
  var onOpenPage: () -> Void = {}

  static let qrSide: CGFloat = 164
  /// Height of the panel itself, for the island's card sizing.
  static let height: CGFloat = 246

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      header
      HStack(alignment: .top, spacing: IslandSpace.m) {
        ReplyQRTile(phase: phase, onRetry: onRetry).frame(width: Self.qrSide, height: Self.qrSide)
        details
      }
      .frame(height: Self.qrSide)
      footer
    }
    .frame(height: Self.height, alignment: .top)
    .animation(NotchMotion.layout(reduceMotion: reduceMotion), value: phase)
    .background {
      if let onClose { Button("", action: onClose).keyboardShortcut(.cancelAction).opacity(0).accessibilityHidden(true) }
    }
  }

  private var header: some View {
    HStack(spacing: IslandSpace.s) {
      Image(systemName: phase == .success ? "checkmark.seal.fill" : "qrcode.viewfinder")
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(phase == .success ? Color.green : IslandInk.secondary)
        .contentTransition(.symbolEffect(.replace))
      Text(verbatim: ReplyLinkText.title(channel, phase: phase, hasDraft: hasDraft))
        .font(IslandFont.headline).foregroundStyle(IslandInk.primary).lineLimit(1)
        .contentTransition(.opacity)
      Spacer(minLength: 0)
      if let onClose {
        Button(action: onClose) {
          Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(IslandInk.primary)
            .frame(width: 20, height: 20).background(IslandFill.raised, in: Circle())
        }
        .buttonStyle(IslandPressStyle())
        .accessibilityLabel(Text(verbatim: L10n.tr("Cancel")))
      }
    }
    .frame(height: 20)
  }

  @ViewBuilder
  private var details: some View {
    VStack(alignment: .leading, spacing: 7) {
      if case .failed(let failure) = phase {
        Text(verbatim: ReplyLinkText.failure(failure, channel: channel))
          .font(IslandFont.body).foregroundStyle(IslandInk.primary).fixedSize(horizontal: false, vertical: true)
        if failure == .needsPassword {
          Button(action: onOpenPage) {
            Text(verbatim: L10n.tr("Open Telegram Web")).font(IslandFont.label).foregroundStyle(.black)
              .padding(.horizontal, 10).frame(height: 24).background(.white, in: Capsule())
          }
          .buttonStyle(IslandPressStyle())
        }
      } else {
        ForEach(Array(ReplyLinkText.steps(channel).enumerated()), id: \.offset) { index, step in
          ReplyLinkStep(number: index + 1, text: step, done: phase == .success || (phase == .linking && index < 2))
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  /// The waiting draft and the privacy line, full width under the code.
  private var footer: some View {
    VStack(alignment: .leading, spacing: 4) {
      if hasDraft, phase != .success {
        Label { Text(verbatim: L10n.tr("Your reply sends as soon as you're linked.")) } icon: {
          Image(systemName: "paperplane.fill")
        }
        .foregroundStyle(IslandInk.secondary)
      }
      Label { Text(verbatim: ReplyLinkText.privacy(channel)) } icon: { Image(systemName: "lock.fill") }
        .foregroundStyle(IslandInk.tertiary).fixedSize(horizontal: false, vertical: true)
    }
    .font(IslandFont.caption).lineLimit(2)
  }
}

private struct ReplyLinkStep: View {
  let number: Int
  let text: String
  let done: Bool

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 6) {
      ZStack {
        Circle().fill(done ? Color.green : IslandFill.raised)
        if done {
          Image(systemName: "checkmark").font(.system(size: 7, weight: .heavy)).foregroundStyle(.black)
        } else {
          Text(verbatim: "\(number)").font(.system(size: 9, weight: .bold, design: .rounded)).foregroundStyle(IslandInk.primary)
        }
      }
      .frame(width: 15, height: 15)
      .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
      Text(verbatim: text).font(IslandFont.label).foregroundStyle(IslandInk.primary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}

/// The white rounded tile: spinner while the code loads, the code, the scan in progress, the
/// success checkmark, or a retry control.
struct ReplyQRTile: View {
  let phase: LinkPhase
  var onRetry: () -> Void = {}

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .fill(phase == .success ? Color.green : Color.white)
      content.transition(.scale(scale: 0.6).combined(with: .opacity))
    }
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
  }

  @ViewBuilder
  private var content: some View {
    switch phase {
    case .loadingCode:
      waiting(L10n.tr("Getting code…")).id("loading")
    case .code(let code):
      if let image = ReplyQRCache.image(for: code) {
        Image(nsImage: image).interpolation(.none).resizable().scaledToFit().padding(12).id("code")
          .accessibilityLabel(Text(verbatim: L10n.tr("QR code")))
      } else {
        waiting(L10n.tr("Getting code…")).id("loading")
      }
    case .linking:
      waiting(L10n.tr("Linking…")).id("linking")
    case .success:
      Image(systemName: "checkmark").font(.system(size: 58, weight: .bold)).foregroundStyle(.white)
        .symbolEffect(.bounce, value: phase == .success).id("success")
    case .failed:
      VStack(spacing: 10) {
        Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 30)).foregroundStyle(.orange)
        Button(action: onRetry) {
          Label { Text(verbatim: L10n.tr("Try Again")) } icon: { Image(systemName: "arrow.clockwise") }
            .font(IslandFont.label).foregroundStyle(.white)
            .padding(.horizontal, 12).frame(height: 26).background(Color.black, in: Capsule())
        }
        .buttonStyle(IslandPressStyle())
      }
      .id("failed")
    }
  }

  private func waiting(_ caption: String) -> some View {
    VStack(spacing: 10) {
      ProgressView().controlSize(.small).tint(.black.opacity(0.55))
      Text(verbatim: caption).font(IslandFont.caption).foregroundStyle(.black.opacity(0.55))
    }
  }
}

/// Decoding and re-encoding a code is not free; the panel redraws often, the code rarely changes.
@MainActor
enum ReplyQRCache {
  private static var last: (code: LinkCode, image: NSImage?)?

  static func image(for code: LinkCode) -> NSImage? {
    if let last, last.code == code { return last.image }
    let image = ReplyQRImage.image(for: code)
    last = (code, image)
    return image
  }
}

/// Observes a linker for the hosts that own one (Settings, onboarding).
struct ReplyLinkPanelHost: View {
  @ObservedObject var linker: ReplyLinker
  var onClose: (() -> Void)?

  var body: some View {
    ReplyLinkPanel(
      channel: linker.channel, phase: linker.phase, onClose: onClose, onRetry: { linker.retry() },
      onOpenPage: { openPage() })
  }

  private func openPage() {
    guard let session = linker.session as? WebMessengerSession else { return }
    WebMessengerConnectWindow.show(for: session)
  }
}
