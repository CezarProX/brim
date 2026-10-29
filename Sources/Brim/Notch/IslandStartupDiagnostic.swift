import AppKit
import ApplicationServices

/// Package smoke test: only the actual island windows, with fresh in-memory display settings.
/// No AppDelegate, permission requests, migrations, capture, updates or background services run.
enum IslandStartupDiagnostic {
    @MainActor static func run(_ app: NSApplication) {
        app.setActivationPolicy(.accessory)
        AppSettings.shared.defaults.setVolatileDomain([
            "notchShelfEnabled": true,
            AppSettings.ShellKey.hideOnFullscreen: false,
            AppSettings.ShellKey.hideInMissionControl: false,
            AppSettings.ShellKey.externalVisibility: "always",
            AppSettings.ShellKey.hiddenApps: [],
            AppSettings.ShellExtraKey.disabledDisplays: []
        ], forName: UserDefaults.argumentDomain)
        var pointer = CGPoint.zero
        let controller = NotchShelfController(pointerLocation: { pointer })
        controller.start()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            var results: [[String: Any]] = []
            for screen in NSScreen.screens {
                guard let presentation = controller.presentation(onScreen: screen.frame),
                      let panel = NSApp.windows.first(where: {
                          $0 is IslandPanel && $0.frame == presentation.geometry.hostingFrame
                      }) else {
                    results.append(["visible": false, "opened": false])
                    continue
                }
                let visible = panel.isVisible && panel.alphaValue > 0.99
                    && (panel.contentView?.bounds.width ?? 0) > 0
                pointer = CGPoint(x: screen.frame.midX, y: screen.frame.minY + 40)
                controller.toggleUnderPointer()
                try? await Task.sleep(for: .milliseconds(400))
                results.append(["visible": visible, "opened": presentation.isExpanded,
                                "floating": presentation.geometry.isFloating])
            }
            let passed = !results.isEmpty && results.allSatisfy {
                $0["visible"] as? Bool == true && $0["opened"] as? Bool == true
            }
            let report: [String: Any] = [
                "passed": passed, "screens": results,
                "screenRecordingGranted": CGPreflightScreenCaptureAccess(),
                "accessibilityGranted": AXIsProcessTrusted()
            ]
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                FileHandle.standardOutput.write(data)
                FileHandle.standardOutput.write(Data("\n".utf8))
            }
            controller.stop()
            exit(passed ? 0 : 1)
        }
        app.run()
    }
}
