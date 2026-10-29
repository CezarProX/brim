import CoreGraphics

/// Telling a flick toward the screen edge (dismiss) from a drag of the file into another app.
/// Translations are in screen points with y up.
enum ThumbnailGesture {
  enum Intent: Equatable { case undecided, swipe, fileDrag }

  /// Movement below this is still a click.
  static let slop: CGFloat = 5
  static let dismissDistance: CGFloat = 80
  static let dismissVelocity: CGFloat = 550

  /// A mostly horizontal move toward the nearest edge is a swipe; anything else drags the file.
  static func intent(translation: CGSize, corner: ThumbnailCorner) -> Intent {
    guard hypot(translation.width, translation.height) >= slop else { return .undecided }
    let outward = translation.width * corner.outward > 0
    return outward && abs(translation.width) > abs(translation.height) * 1.3 ? .swipe : .fileDrag
  }

  /// The card follows the pointer toward the edge and resists (rubber-bands) the other way.
  static func swipeOffset(translationX: CGFloat, corner: ThumbnailCorner) -> CGFloat {
    let outward = translationX * corner.outward
    return outward >= 0 ? translationX : translationX * 0.2
  }

  /// Far enough, or fast enough, toward the edge closes the card; otherwise it springs back.
  static func swipeDismisses(offset: CGFloat, velocity: CGFloat, corner: ThumbnailCorner) -> Bool {
    offset * corner.outward >= dismissDistance || velocity * corner.outward >= dismissVelocity
  }
}
