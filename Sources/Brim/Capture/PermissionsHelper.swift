import AppKit

enum PermissionsHelper {
    @MainActor private static var isShowingRecovery = false

    /// Called only after ScreenCaptureKit rejects an explicit capture request.
    /// System Settings can show an old build's grant after its identity changes.
    @MainActor
    static func showScreenRecordingRecovery() {
        guard !isShowingRecovery else { return }
        isShowingRecovery = true
        defer { isShowingRecovery = false }

        let content = BrimDialogContent(
            title: L10n.tr("Allow Brim to see your screen"),
            message: L10n.tr("macOS didn’t let this copy of Brim capture the screen."),
            points: [
                .init(symbol: "gearshape",
                      text: L10n.tr("In System Settings > Privacy & Security > Screen & System Audio Recording, turn on Brim.")),
                .init(symbol: "arrow.clockwise", text: L10n.tr("Then quit Brim and open it again.")),
                .init(symbol: "plus.circle",
                      text: L10n.tr("Already on? Remove Brim from the list with −, then add it again with +. macOS can treat a rebuilt copy as a new app.")),
            ],
            confirmTitle: L10n.tr("Open System Settings"),
            cancelTitle: L10n.tr("Not Now"))
        if BrimDialog.run(content),
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}
