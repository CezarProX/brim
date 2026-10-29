import AppKit

/// Watches system-wide mouse drags (never keys) to learn when files are being dragged.
/// The notch opens its drop targets and the shake gesture opens quick actions from this.
@MainActor
final class FileDragWatcher {
  static let shared = FileDragWatcher()
  /// True while a drag that carries file URLs is in flight.
  private(set) var isDraggingFiles = false
  var onShake: ((CGPoint) -> Void)?
  /// The mouse came up while files were being dragged, at this screen point.
  var onRelease: ((CGPoint) -> Void)?
  var onEnd: (() -> Void)?
  private var monitors: [Any] = []
  private var detector = JiggleDetector()
  private var shakeGate = DragShakeGate()
  private var baseline = NSPasteboard(name: .drag).changeCount
  private var endWork: DispatchWorkItem?

  func start() {
    guard monitors.isEmpty else { return }
    if let down = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown, handler: { [weak self] _ in
      Task { @MainActor in self?.mouseDown() }
    }) { monitors.append(down) }
    if let drag = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged, handler: { [weak self] event in
      let location = NSEvent.mouseLocation
      let time = event.timestamp
      Task { @MainActor in self?.dragged(to: location, time: time) }
    }) { monitors.append(drag) }
    if let up = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp, handler: { [weak self] _ in
      let location = NSEvent.mouseLocation
      Task { @MainActor in self?.mouseUp(at: location) }
    }) { monitors.append(up) }
  }

  /// Applies the shake sensitivity setting (1 hard … 5 easy).
  func setSensitivity(_ level: Int) { detector = JiggleDetector(sensitivity: level) }

  func stop() {
    monitors.forEach(NSEvent.removeMonitor)
    monitors.removeAll()
    isDraggingFiles = false
  }

  private func mouseDown() {
    endWork?.cancel()
    detector.reset()
    baseline = NSPasteboard(name: .drag).changeCount
    isDraggingFiles = false
  }

  private func dragged(to location: CGPoint, time: TimeInterval) {
    if !isDraggingFiles {
      // Only a real drag of files updates the drag pasteboard; selection drags don't.
      let board = NSPasteboard(name: .drag)
      isDraggingFiles = board.changeCount != baseline && board.types?.contains(.fileURL) == true
    }
    guard isDraggingFiles, detector.add(x: location.x, y: location.y, time: time),
      shakeGate.admit(drag: NSPasteboard(name: .drag).changeCount)
    else { return }
    onShake?(location)
  }

  private func mouseUp(at location: CGPoint) {
    if isDraggingFiles { onRelease?(location) }
    // Let a drop land on a target before the targets disappear.
    let work = DispatchWorkItem { [weak self] in
      self?.isDraggingFiles = false
      self?.onEnd?()
    }
    endWork = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
  }
}
