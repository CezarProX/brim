import AVFoundation
import AppKit
import SwiftUI

/// Plays a banner loop with its alpha intact. Muted, never takes focus, and costs nothing when
/// stopped: `stop()` pauses, ends the loop and releases the player and its decoder. A poster frame
/// covers the moment before the first decoded frame so the card never flashes empty.
final class AirPodsBannerPlayerView: NSView {
  let url: URL
  private(set) var player: AVQueuePlayer?
  private var looper: AVPlayerLooper?
  private let poster = CALayer()
  private var readyObservation: NSKeyValueObservation?
  var playerLayer: AVPlayerLayer? { layer as? AVPlayerLayer }
  var isPlaying: Bool { (player?.rate ?? 0) > 0 }
  var showsPoster: Bool { !poster.isHidden }

  init(url: URL, poster image: NSImage? = nil) {
    self.url = url
    super.init(frame: .zero)
    wantsLayer = true
    poster.contents = image
    poster.contentsGravity = .resizeAspect
    poster.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
    layer?.addSublayer(poster)
    readyObservation = playerLayer?.observe(\.isReadyForDisplay, options: [.new]) { [weak self] layer, _ in
      let ready = layer.isReadyForDisplay
      DispatchQueue.main.async { self?.setPosterHidden(ready && self?.player != nil) }
    }
  }

  override func layout() {
    super.layout()
    poster.frame = bounds
  }

  private func setPosterHidden(_ hidden: Bool) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    poster.isHidden = hidden
    CATransaction.commit()
  }

  required init?(coder: NSCoder) { nil }

  override func makeBackingLayer() -> CALayer {
    let layer = AVPlayerLayer()
    layer.videoGravity = .resizeAspect
    layer.backgroundColor = NSColor.clear.cgColor
    layer.isOpaque = false
    layer.pixelBufferAttributes = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
    return layer
  }

  override var acceptsFirstResponder: Bool { false }
  override func hitTest(_ point: NSPoint) -> NSView? { nil }

  func start() {
    if let player { player.play(); return }
    let queue = AVQueuePlayer()
    queue.isMuted = true
    queue.preventsDisplaySleepDuringVideoPlayback = false
    looper = AVPlayerLooper(player: queue, templateItem: AVPlayerItem(url: url))
    playerLayer?.player = queue
    player = queue
    queue.play()
  }

  func stop() {
    player?.pause()
    looper?.disableLooping()
    playerLayer?.player = nil
    looper = nil
    player = nil
    setPosterHidden(false)
  }
}

/// SwiftUI host for `AirPodsBannerPlayerView`: plays while `playing`, fully stopped otherwise.
struct AirPodsBannerVideoView: NSViewRepresentable {
  let url: URL
  var poster: NSImage? = nil
  let playing: Bool

  func makeNSView(context: Context) -> AirPodsBannerPlayerView {
    let view = AirPodsBannerPlayerView(url: url, poster: poster)
    if playing { view.start() }
    return view
  }

  func updateNSView(_ view: AirPodsBannerPlayerView, context: Context) {
    if playing { view.start() } else { view.stop() }
  }

  static func dismantleNSView(_ view: AirPodsBannerPlayerView, coordinator: ()) {
    view.stop()
  }
}
