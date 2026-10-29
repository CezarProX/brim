import Foundation

/// The user's tile layout, persisted through AppSettings.
@MainActor
final class CommandCenterStore: ObservableObject {
  static let shared = CommandCenterStore()

  @Published private(set) var placements: [TilePlacement]
  @Published var isEditing = false
  private let settings: AppSettings

  init(settings: AppSettings = .shared) {
    self.settings = settings
    placements = CommandCenterLayout.parse(settings.commandCenterLayout)
  }

  var pages: [[PlacedTile]] { CommandCenterLayout.paginate(placements) }
  var pageCount: Int { CommandCenterLayout.pageCount(placements) }

  func add(_ kind: TileKind) { commit(CommandCenterLayout.adding(kind, to: placements)) }
  func remove(_ kind: TileKind) { commit(CommandCenterLayout.removing(kind, from: placements)) }
  func move(_ kind: TileKind, onto target: TileKind) {
    commit(CommandCenterLayout.moving(kind, onto: target, in: placements))
  }
  func shift(_ kind: TileKind, by offset: Int) {
    commit(CommandCenterLayout.shifting(kind, by: offset, in: placements))
  }
  func cycleSize(_ kind: TileKind) { commit(CommandCenterLayout.cyclingSize(kind, in: placements)) }
  func apply(_ preset: CommandCenterLayout.Preset) { commit(preset.placements) }
  func reload() { placements = CommandCenterLayout.parse(settings.commandCenterLayout) }

  private func commit(_ next: [TilePlacement]) {
    placements = next
    settings.commandCenterLayout = CommandCenterLayout.storageString(next)
  }
}
