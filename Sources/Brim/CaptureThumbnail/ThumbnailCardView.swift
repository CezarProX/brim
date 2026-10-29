import SwiftUI

/// The floating capture card: a dark glass rounded card with the capture centred in it. Hovering
/// reveals close and pin at the top, "Copy" and "Save" in the middle, edit and copy-text below.
struct ThumbnailCardView: View {
  @ObservedObject var model: ThumbnailCardModel
  let services: ThumbnailServices
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  static let imageInset: CGFloat = 14
  private let size = ThumbnailLayout.cardSize
  private let radius = ThumbnailLayout.cornerRadius

  var body: some View {
    card
      .frame(width: size.width, height: size.height)
      .onHover { model.setHovered($0) }
      .scaleEffect(scale, anchor: model.corner.isBottom ? .bottom : .top)
      .offset(x: offset)
      .opacity(opacity)
      .animation(motion, value: model.isPresented)
      .animation(motion, value: model.isDismissed)
      .animation(model.swipeOffset == 0 ? NotchMotion.layout(reduceMotion: reduceMotion) : nil, value: model.swipeOffset)
      .padding(ThumbnailLayout.shadowInset)
  }

  private var card: some View {
    ZStack {
      background
      thumbnail
      ThumbnailDragSurface(model: model, services: services, imageInset: Self.imageInset)
      scrim
      if showsControls { controls.transition(.opacity) }
      if let feedback = model.feedback {
        ThumbnailFeedbackBadge(feedback: feedback)
          .transition(.scale(scale: 0.85).combined(with: .opacity))
      }
      if model.isPinned && !model.isHovered { pinBadge.transition(.opacity) }
    }
    .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    .shadow(color: .black.opacity(GlassTokens.of(.panel).shadow), radius: 16, y: 7)
    .opacity(model.isDraggingOut ? 0.55 : 1)
    .animation(NotchMotion.feedback(reduceMotion: reduceMotion), value: model.isHovered)
    .animation(NotchMotion.layout(reduceMotion: reduceMotion), value: model.feedback)
    .animation(NotchMotion.feedback(reduceMotion: reduceMotion), value: model.isDraggingOut)
  }

  /// Dark glass tinted by the capture itself (a soft colour wash of it), so letterboxed bands around
  /// wide or tall captures pick up its colours instead of reading as empty black.
  private var background: some View {
    ZStack {
      // The shared floating-panel glass (`GlassStyle`): blur, readability tint, sheen and rim.
      GlassSurface(
        role: .panel, shape: RoundedRectangle(cornerRadius: radius, style: .continuous), showsShadow: false)
      if let backdrop = model.backdrop {
        Image(nsImage: backdrop)
          .resizable()
          .interpolation(.high)
          .frame(width: size.width, height: size.height)
          .opacity(0.22)
      }
    }
    .allowsHitTesting(false)
  }

  private var thumbnail: some View {
    Image(nsImage: model.image)
      .resizable()
      .interpolation(.high)
      .aspectRatio(contentMode: .fit)
      .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5))
      .shadow(color: .black.opacity(0.4), radius: 8, y: 3)
      .padding(Self.imageInset)
      .accessibilityLabel(L10n.tr("Screenshot preview"))
  }

  /// Dims the capture so the controls and confirmations read on any screenshot.
  private var scrim: some View {
    Rectangle()
      .fill(Color.black.opacity(model.isHovered || model.feedback != nil ? 0.38 : 0))
      .allowsHitTesting(false)
  }

  private var showsControls: Bool { model.isHovered && model.feedback == nil && !model.isDraggingOut }

  private var controls: some View {
    VStack(spacing: 0) {
      HStack {
        ThumbnailIconButton(symbol: "xmark", help: L10n.tr("Close")) { model.perform(.close) }
        Spacer()
        ThumbnailIconButton(
          symbol: model.isPinned ? "pin.fill" : "pin", help: model.isPinned ? L10n.tr("Unpin") : L10n.tr("Pin"),
          isActive: model.isPinned
        ) { model.perform(.togglePin) }
      }
      Spacer()
      VStack(spacing: 8) {
        ThumbnailPillButton(title: L10n.tr("Copy")) { model.perform(.copy) }
        ThumbnailPillButton(title: L10n.tr("Save")) { model.perform(.save) }
      }
      Spacer()
      HStack {
        ThumbnailIconButton(symbol: "pencil", help: L10n.tr("Edit")) { model.perform(.edit) }
        Spacer()
        ThumbnailIconButton(symbol: "text.viewfinder", help: L10n.tr("Copy Text")) { model.perform(.recognizeText) }
      }
    }
    .padding(10)
  }

  private var pinBadge: some View {
    Image(systemName: "pin.fill")
      .font(.system(size: 9, weight: .bold))
      .foregroundStyle(.black)
      .frame(width: 20, height: 20)
      .background(Circle().fill(Color.white))
      .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
      .padding(10)
      .allowsHitTesting(false)
  }

  // MARK: Motion

  private var isOnScreen: Bool { model.isPresented && !model.isDismissed }
  private var slides: Bool { !reduceMotion }

  private var offset: CGFloat {
    if !slides { return 0 }
    if !isOnScreen { return ThumbnailLayout.offscreenOffset(for: model.corner) }
    return model.swipeOffset
  }

  private var scale: CGFloat { slides && !isOnScreen ? 0.86 : 1 }
  private var opacity: Double {
    guard isOnScreen else { return slides ? 0.4 : 0 }
    return 1
  }

  /// Arrivals use the island's opening spring (a small overshoot); exits its critically damped close.
  /// Reduce Motion fades instead.
  private var motion: Animation? {
    if reduceMotion { return .easeInOut(duration: 0.25) }
    return NotchMotion.expansion(isOnScreen, reduceMotion: false)
  }
}
