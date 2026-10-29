import SwiftUI

/// The device picture on the AirPods connect card. This is the only seam between the card / HUD
/// logic and how the picture is produced: the card hands over what the device is and whether the
/// card is on screen, nothing else.
///
/// Fallback chain: macOS's own banner loop for this device (read from the system, see
/// `AirPodsBannerClip`), then the procedural SceneKit model, then the SF Symbol. Every source plays
/// only while `active`, shows a still under Reduce Motion, and is decorative to VoiceOver.
struct AirPodsVisual: View {
  let kind: AirPodsDeviceKind?
  var productID: Int? = nil
  let symbol: String
  /// The 168 px system clips stay sharp up to 84 pt on Retina.
  var size: CGFloat = 72
  var active = true
  var clips = AirPodsBannerClip()
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.airPodsVisualStillTime) private var stillTime

  var body: some View {
    Group {
      if let url = clips.url(productID: productID, kind: kind) {
        banner(url)
      } else {
        AirPodsModelView(kind: kind, symbol: symbol, size: size, active: active)
      }
    }
    .frame(width: size, height: size)
    .accessibilityHidden(true)
  }

  /// The player exists only while the card is showing and motion is allowed; otherwise a still
  /// frame stands in (no decoder alive). The player shows the same frame as its poster until ready.
  @ViewBuilder
  private func banner(_ url: URL) -> some View {
    let still = AirPodsBannerStills.frame(url, at: stillTime ?? 0)
    if stillTime == nil, active, !reduceMotion {
      AirPodsBannerVideoView(url: url, poster: still, playing: true)
    } else if let still {
      Image(nsImage: still).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
    }
  }
}

private struct AirPodsVisualStillTimeKey: EnvironmentKey {
  static let defaultValue: TimeInterval? = nil
}

extension EnvironmentValues {
  /// When set, `AirPodsVisual` draws a still at this time of its animation instead of playing it
  /// (render tests and preview export: SwiftUI's ImageRenderer cannot capture live layers).
  var airPodsVisualStillTime: TimeInterval? {
    get { self[AirPodsVisualStillTimeKey.self] }
    set { self[AirPodsVisualStillTimeKey.self] = newValue }
  }
}
