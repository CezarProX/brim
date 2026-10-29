import Foundation

/// One place to start and stop every Droplet this package adds. Each start is a no-op unless the
/// user turned that feature on, so calling this at launch costs nothing for a default install.
enum Droplets {
  @MainActor static func start() {
    FinderServicesProvider.shared.start()
    RingMenuController.shared.start()
    EmojiPickerController.shared.start()
    if AppSettings.shared.mcpEnabled { MCPSocketServer.shared.start() }
    AgentQuestionBridge.shared.startIfEnabled()
    XcodeBuildModel.shared.start()
    StayAwakeController.shared.start()
    ThunderstormController.shared.start()
    MenuBarManagerController.shared.start()
    if AppSettings.shared.localSendEnabled { Task { await LocalSendModel.shared.start() } }
  }

  /// Releases sockets, assertions and lid-closed mode. Call from `applicationWillTerminate`.
  @MainActor static func shutdown() {
    MCPSocketServer.shared.stop()
    AgentQuestionBridge.shared.shutdown()
    LocalSendModel.shared.stop()
    StayAwakeController.shared.shutdown()
    ThunderstormController.shared.close()
    MenuBarManagerController.shared.shutdown()
  }
}
