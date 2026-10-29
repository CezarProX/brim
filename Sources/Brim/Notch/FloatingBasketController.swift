import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

/// Files caught mid-drag. A tray holds references only and forgets them when closed.
@MainActor
final class BasketModel: ObservableObject, Identifiable {
  let id = UUID()
  @Published private(set) var urls: [URL] = []
  @Published var isHovered = false

  func add(_ incoming: [URL]) {
    let fresh = incoming.filter { url in url.isFileURL && !urls.contains(url) }
    guard !fresh.isEmpty else { return }
    urls = Array((urls + fresh).prefix(50))
  }

  func remove(_ url: URL) { urls.removeAll { $0 == url } }

  /// Mirrors another tray; a no-op when the files already match (so syncing never loops).
  func replace(with other: [URL]) {
    guard let next = TraySync.mirror(source: other, target: urls) else { return }
    urls = next
  }
  func clear() { urls = [] }

  func drop(_ providers: [NSItemProvider]) -> Bool {
    FileDropLoader.load(providers) { [weak self] urls in self?.add(urls) }
  }
}

/// One tab of the tray switcher.
struct FloatingTrayTab: Identifiable, Equatable {
  let id: UUID
  let number: Int
  let count: Int
}

/// What every open tray needs to draw its switcher.
@MainActor
final class FloatingTrayRegistry: ObservableObject {
  @Published fileprivate(set) var tabs: [FloatingTrayTab] = []
  @Published fileprivate(set) var activeID: UUID?
  var onSelect: (UUID) -> Void = { _ in }
}

@MainActor
private final class FloatingTray {
  let model = BasketModel()
  let number: Int
  var panel: NSPanel
  var autoHide: Task<Void, Never>?
  var subscriptions: Set<AnyCancellable> = []

  init(number: Int, panel: NSPanel) {
    self.number = number
    self.panel = panel
  }
}

/// Shake the pointer while dragging files and a tray appears beside it to hold them.
/// With several trays enabled, each further shake opens another tray (up to four).
@MainActor
final class FloatingBasketController {
  static let shared = FloatingBasketController()
  private var trays: [FloatingTray] = []
  private let registry = FloatingTrayRegistry()
  private var quickActions: NSPanel?
  private var quickActionTargets: [DropTarget] = []
  /// The drag (drag pasteboard change count) whose files were already delivered.
  private var deliveredDrag: Int?
  /// Where the mouse came up during the last file drag, for delivery once the drop has had its chance.
  private var releasePoint: CGPoint?
  private var nextNumber = 1

  var isEnabled: Bool { AppSettings.shared.basketEnabled }
  var openTrayCount: Int { trays.count }

  /// Shaking a file drag opens a tray beside the pointer and the quick action tiles on the other side.
  func start() {
    let watcher = FileDragWatcher.shared
    watcher.setSensitivity(AppSettings.shared.shakeSensitivity)
    watcher.start()
    registry.onSelect = { [weak self] id in self?.focus(id) }
    watcher.onShake = { [weak self] location in
      guard let self, self.isEnabled else { return }
      self.shake(at: location)
    }
    watcher.onRelease = { [weak self] point in self?.releasePoint = point }
    watcher.onEnd = { [weak self] in self?.endDrag() }
  }

  func stop() {
    FileDragWatcher.shared.stop()
    hideQuickActions()
  }

  func settingsChanged() {
    FileDragWatcher.shared.setSensitivity(AppSettings.shared.shakeSensitivity)
    if !isEnabled { hideQuickActions() }
    trays.forEach(refreshAutoHide)
  }

  // MARK: Receiving files

  private func shake(at location: CGPoint) {
    let opensTray = TrayRouting.shakeOpensFloatingTray(AppSettings.shared.trayPlacement)
    let action = FloatingTrayPolicy.onShake(openTrays: trays.count, multiple: AppSettings.shared.floatingTrayMultiple)
    switch action {
    case .createNew: if opensTray { _ = makeTray(near: location) }
    case .reuseLatest: if opensTray, let tray = trays.last { place(tray, near: location) }
    }
    showQuickActions(near: location)
  }

  /// Adds files to the active tray, opening one if none is open.
  func receive(_ urls: [URL], near location: CGPoint = NSEvent.mouseLocation) {
    let tray = activeTray ?? makeTray(near: location)
    tray.model.add(urls)
    tray.panel.orderFrontRegardless()
    activate(tray)
  }

  /// Opens a tray (or brings the active one forward) without adding files.
  func show(near location: CGPoint) {
    if let tray = activeTray { place(tray, near: location) } else { _ = makeTray(near: location) }
  }

  /// Delivers a drag's files to the tile or tray under the release point. The panels' SwiftUI drop
  /// targets miss drags that start while they open (the macOS screenshot thumbnail, our capture card),
  /// so the release itself delivers; whichever path comes first wins. Returns whether something took them.
  func finishDrag(_ urls: [URL], at point: CGPoint) -> Bool {
    guard hasDropTarget(at: point) else { return false }
    defer { hideQuickActions() }
    guard claimDrag() else { return true }
    let files = DroppedFileKeeper.lasting(urls)
    if let panel = quickActions, panel.frame.contains(point) {
      let local = CGPoint(x: point.x - panel.frame.minX, y: panel.frame.maxY - point.y)
      guard let target = FloatingTrayLayout.target(at: local, in: quickActionTargets) else { return false }
      FileDropActions.perform(target, files) { NotchShelfController.shared.presentConvert($0) }
      return true
    }
    guard let tray = tray(at: point) else { return false }
    tray.model.add(files)
    activate(tray)
    return true
  }

  /// The drag is over: when it was released on our panels and no drop target took it, deliver the
  /// dragged files from the drag pasteboard. Promised files (no file yet) are left to the drop targets.
  private func endDrag() {
    defer { releasePoint = nil; hideQuickActions() }
    let drag = NSPasteboard(name: .drag).changeCount
    guard let point = releasePoint, hasDropTarget(at: point), FileDropLoader.loadingDrag != drag else { return }
    let urls = (NSPasteboard(name: .drag).readObjects(
      forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? [])
      .filter { FileManager.default.fileExists(atPath: $0.path) }
    guard !urls.isEmpty else { return }
    _ = finishDrag(urls, at: point)
  }

  /// True the first time it's asked for the current drag.
  private func claimDrag() -> Bool {
    let drag = NSPasteboard(name: .drag).changeCount
    guard deliveredDrag != drag else { return false }
    deliveredDrag = drag
    return true
  }

  /// True when a drop at the point would land on the quick action tiles or a floating tray.
  func hasDropTarget(at point: CGPoint) -> Bool {
    (quickActions?.frame.contains(point) ?? false) || tray(at: point) != nil
  }

  /// The topmost open tray under the point.
  private func tray(at point: CGPoint) -> FloatingTray? {
    trays.last { $0.panel.isVisible && $0.panel.frame.contains(point) }
  }

  /// True when the point is on an open floating tray (drag-out tracking).
  func containsTray(at point: CGPoint) -> Bool {
    trays.contains { $0.panel.isVisible && $0.panel.frame.contains(point) }
  }

  private var activeTray: FloatingTray? {
    trays.first { $0.model.id == registry.activeID } ?? trays.last
  }

  // MARK: Trays

  private func trayFrame(near location: CGPoint, index: Int) -> CGRect {
    let size = FloatingTrayLayout.size
    let screen = NSScreen.screens.first { $0.frame.contains(location) } ?? NSScreen.main
    let origin = FloatingTrayPolicy.origin(
      near: location, size: size, index: index, bounds: screen?.visibleFrame ?? .zero)
    return CGRect(origin: origin, size: size)
  }

  private func makeTray(near location: CGPoint) -> FloatingTray {
    let panel = NSPanel(
      contentRect: trayFrame(near: location, index: trays.count), styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered, defer: false)
    panel.isReleasedWhenClosed = false
    panel.backgroundColor = .clear
    panel.isOpaque = false
    panel.hasShadow = false
    panel.level = .floating
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.isMovableByWindowBackground = true
    let tray = FloatingTray(number: nextNumber, panel: panel)
    nextNumber += 1
    panel.contentView = NSHostingView(rootView: BasketView(
      model: tray.model, registry: registry, number: tray.number,
      close: { [weak self, weak tray] in if let tray { self?.close(tray) } }))
    panel.alphaValue = 0
    panel.orderFrontRegardless()
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.18
      panel.animator().alphaValue = 1
    }
    if AppSettings.shared.floatingTraySync, let existing = activeTray { tray.model.replace(with: existing.model.urls) }
    trays.append(tray)
    tray.model.$urls.dropFirst().sink { [weak self, weak tray] urls in
      guard let self, let tray else { return }
      if AppSettings.shared.floatingTraySync {
        for other in self.trays where other !== tray { other.model.replace(with: urls) }
      }
      self.publishTabs()
      self.refreshAutoHide(tray)
    }.store(in: &tray.subscriptions)
    tray.model.$isHovered.removeDuplicates().sink { [weak self, weak tray] hovered in
      guard let self, let tray else { return }
      if hovered { self.activate(tray) }
      self.refreshAutoHide(tray)
    }.store(in: &tray.subscriptions)
    activate(tray)
    refreshAutoHide(tray)
    return tray
  }

  private func place(_ tray: FloatingTray, near location: CGPoint) {
    let index = trays.firstIndex { $0 === tray } ?? 0
    tray.panel.animator().setFrame(trayFrame(near: location, index: index), display: true)
    tray.panel.orderFrontRegardless()
    activate(tray)
  }

  private func focus(_ id: UUID) {
    guard let tray = trays.first(where: { $0.model.id == id }) else { return }
    tray.panel.orderFrontRegardless()
    activate(tray)
  }

  private func activate(_ tray: FloatingTray) {
    guard registry.activeID != tray.model.id else { return }
    registry.activeID = tray.model.id
  }

  private func publishTabs() {
    registry.tabs = trays.map { FloatingTrayTab(id: $0.model.id, number: $0.number, count: $0.model.urls.count) }
  }

  /// Closes every open tray (the filmed demo tidies up with this).
  func closeAll() { trays.forEach(close) }

  private func close(_ tray: FloatingTray) {
    guard let index = trays.firstIndex(where: { $0 === tray }) else { return }
    trays.remove(at: index)
    tray.autoHide?.cancel()
    tray.subscriptions.removeAll()
    if registry.activeID == tray.model.id { registry.activeID = trays.last?.model.id }
    if trays.isEmpty { nextNumber = 1 }
    publishTabs()
    let panel = tray.panel
    NSAnimationContext.runAnimationGroup({ context in
      context.duration = 0.14
      panel.animator().alphaValue = 0
    }, completionHandler: { panel.orderOut(nil) })
    tray.model.clear()
  }

  /// Closes an empty, untouched tray after the auto-hide delay.
  private func refreshAutoHide(_ tray: FloatingTray) {
    tray.autoHide?.cancel()
    let seconds = AppSettings.shared.floatingTrayAutoHideSeconds
    guard seconds > 0, tray.model.urls.isEmpty, !tray.model.isHovered else { return }
    tray.autoHide = Task { @MainActor [weak self, weak tray] in
      try? await Task.sleep(for: .seconds(seconds))
      guard !Task.isCancelled, let self, let tray, tray.model.urls.isEmpty, !tray.model.isHovered else { return }
      self.close(tray)
    }
  }

  // MARK: Quick actions

  /// The tiles a shake brings up beside the pointer (also opened by the filmed demo).
  func showQuickActions(near location: CGPoint) {
    guard quickActions == nil else { return }
    let targets = AppSettings.shared.quickActionTargets.filter { $0 != .basket }
    quickActionTargets = targets
    let size = FloatingTrayLayout.quickActionsSize(tileCount: targets.count)
    let frame = CGRect(x: location.x - size.width - 30, y: location.y - size.height / 2, width: size.width, height: size.height)
    let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    panel.isReleasedWhenClosed = false
    panel.backgroundColor = .clear
    panel.isOpaque = false
    panel.hasShadow = true
    panel.level = .floating
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.contentView = NSHostingView(rootView: QuickActionsView(targets: targets, size: size) { [weak self] target, urls in
      guard let self else { return }
      self.hideQuickActions()
      guard self.claimDrag() else { return }
      FileDropActions.perform(target, DroppedFileKeeper.lasting(urls)) { NotchShelfController.shared.presentConvert($0) }
    })
    panel.orderFrontRegardless()
    quickActions = panel
  }

  func hideQuickActions() {
    quickActions?.orderOut(nil)
    quickActions = nil
  }
}

enum FloatingTrayLayout {
  static let size = CGSize(width: 280, height: 190)
  static let tileHeight: CGFloat = 132
  static let tileSpacing: CGFloat = 12
  static let padding: CGFloat = 14
  static let cornerRadius: CGFloat = 34
  static let width: CGFloat = 340

  static func quickActionsSize(tileCount: Int) -> CGSize {
    let rows = CGFloat(max(1, (tileCount + 1) / 2))
    return CGSize(width: width, height: rows * tileHeight + (rows - 1) * tileSpacing + 2 * padding)
  }

  /// The tile under a point measured from the panel's top-left; gaps count toward the nearest tile.
  static func target(at point: CGPoint, in targets: [DropTarget]) -> DropTarget? {
    let rows = rows(targets)
    guard !rows.isEmpty, point.x >= 0, point.y >= 0, point.x <= width else { return nil }
    let row = min(rows.count - 1, max(0, Int((point.y - padding) / (tileHeight + tileSpacing))))
    let tiles = rows[row]
    return tiles.count == 1 || point.x < width / 2 ? tiles[0] : tiles[1]
  }

  /// Pairs of tiles; an odd count leaves the last one alone on its row.
  static func rows(_ targets: [DropTarget]) -> [[DropTarget]] {
    stride(from: 0, to: targets.count, by: 2).map { Array(targets[$0..<min($0 + 2, targets.count)]) }
  }
}
