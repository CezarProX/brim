import Foundation

/// Always-on state the closed island shows as quiet activities: Focus and Personal Hotspot.
/// (Camera and microphone live in `SystemSignalsMonitor`.)
@MainActor
final class SystemStatusIndicators: ObservableObject {
  static let shared = SystemStatusIndicators()
  @Published private(set) var focusOn = false
  @Published private(set) var focusName: String?
  @Published private(set) var hotspot = false

  func setFocus(_ on: Bool, name: String? = nil) {
    if focusOn != on { focusOn = on }
    if focusName != name { focusName = name }
  }

  func setHotspot(_ on: Bool) { if hotspot != on { hotspot = on } }

  /// For previews and render tests.
  func preview(focus: Bool, hotspot: Bool) {
    focusOn = focus
    self.hotspot = hotspot
  }
}
