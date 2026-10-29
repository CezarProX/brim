// main.swift
// Brim — a macOS menu-bar screenshot utility (Lightshot-style).
//
// Entry point: builds the shared NSApplication, installs the AppDelegate,
// hides the Dock icon (menu-bar-only "accessory" app), and runs the main
// run loop.

import AppKit

// `Brim --mcp` is an MCP stdio server for AI apps; it never starts the UI.
if CommandLine.arguments.contains("--mcp") { MCPBridge.runAndExit() }

// `Brim --agent-hook` is the Claude Code hook command for answering agent questions; no UI.
if CommandLine.arguments.contains("--agent-hook") { AgentHook.runAndExit() }

// Top-level code in `main.swift` runs synchronously on the main thread before
// any run loop starts, but isn't implicitly @MainActor-isolated to the
// compiler. `assumeIsolated` asserts what's already true at runtime (this is
// the main thread) so the MainActor-isolated `AppDelegate` can be constructed
// here without hopping through an async context.
MainActor.assumeIsolated {
    if CommandLine.arguments.contains("--island-smoke-test") {
        IslandStartupDiagnostic.run(NSApplication.shared)
        exit(0)
    }
    // Data and preferences from builds made before the rename move over before anything reads them.
    LegacyMigration.run()
    let app = NSApplication.shared
    if CommandLine.arguments.contains("--music-status") {
        // Read-only: what Brim can see, without pressing anything in the player.
        app.setActivationPolicy(.accessory)
        Task {
            var lines = ["AX trusted: \(NowPlayingAccessibility.isTrusted)"]
            let provider = NowPlayingProvider()
            let sources = await provider.runningSources()
            lines.append("Sources: \(sources.map(\.rawValue).joined(separator: ","))")
            for source in sources {
                do {
                    if let snapshot = try await provider.snapshot(source) {
                        lines.append("\(source.rawValue): playing=\(snapshot.isPlaying) title=\(!snapshot.title.isEmpty) artist=\(!snapshot.artist.isEmpty) art=\(snapshot.artworkURL != nil)")
                    } else {
                        lines.append("\(source.rawValue): no snapshot")
                    }
                } catch { lines.append("\(source.rawValue): failed: \(error)") }
            }
            lines += NowPlayingAccessibility.survey()
            // Exercise the same stream/poll reconciliation that feeds Home, across two polls.
            // Reading the app adapters alone misses a valid system song being erased by a poll.
            let model = NowPlayingModel()
            model.start()
            try? await Task.sleep(for: .seconds(9))
            lines.append("Model: stream=\(model.streamAlive) track=\(model.track != nil) playing=\(model.track?.isPlaying == true) inIsland=\(model.isInIsland())")
            model.stop()
            try? lines.joined(separator: "\n").write(to: URL(fileURLWithPath: "/tmp/Brim-music-status.txt"), atomically: true, encoding: .utf8)
            app.terminate(nil)
        }
        app.run()
        exit(0)
    }
    if CommandLine.arguments.contains("--queue-probe") {
        // Read-only apart from opening (then closing) one row's menu: the Play next path, step by step.
        app.setActivationPolicy(.accessory)
        Task {
            var lines: [String] = []
            let model = NowPlayingModel()
            model.start()
            try? await Task.sleep(for: .seconds(6))
            if let track = model.track {
                let snapshot = track.snapshot
                lines.append("Track: source=\(snapshot.source.rawValue) title=\(snapshot.title)")
                do {
                    let items = try await YouTubeMusicQueueReader.upcoming(after: snapshot, limit: 12)
                    lines.append("Upcoming: " + items.prefix(4).map(\.title).joined(separator: " | "))
                    if let item = items.dropFirst().first {
                        let opened = try await YouTubeMusicQueueReader.runInTabs(
                            for: snapshot.source, javaScript: try YouTubeMusicQueueReader.openMenuScript(title: item.title, current: snapshot.title))
                        lines.append("Open menu for \(item.title): \(YouTubeMusicQueueReader.statuses(opened))")
                        _ = try? await YouTubeMusicQueueReader.runInTabs(for: snapshot.source, javaScript:
                            "(() => { document.dispatchEvent(new KeyboardEvent('keydown', {key: 'Escape', bubbles: true})); return 'closed'; })()")
                    }
                } catch { lines.append("Failed: \(error.localizedDescription)") }
            } else { lines.append("No track") }
            model.stop()
            try? lines.joined(separator: "\n").write(to: URL(fileURLWithPath: "/tmp/Brim-queue-probe.txt"), atomically: true, encoding: .utf8)
            app.terminate(nil)
        }
        app.run()
        exit(0)
    }
    if CommandLine.arguments.contains("--music-diagnostic") {
        app.setActivationPolicy(.accessory)
        Task {
            var lines = ["AX trusted: \(NowPlayingAccessibility.isTrusted)"]
            let provider = NowPlayingProvider()
            let sources = await provider.runningSources()
            lines.append("Sources: \(sources.map(\.rawValue).joined(separator: ","))")
            for source in sources {
                do {
                    guard let initial = try await provider.snapshot(source) else {
                        lines.append("\(source.rawValue): no snapshot")
                        continue
                    }
                    lines.append("\(source.rawValue): artist=\(initial.artist.count), art=\(initial.artworkURL != nil), playing=\(initial.isPlaying)")
                    guard initial.isPlaying else { continue }
                    do {
                        try await provider.perform(.playPause, expected: initial, token: NowPlayingActionToken())
                        lines.append("\(source.rawValue): pause succeeded")
                    } catch { lines.append("\(source.rawValue): pause failed: \(error)") }
                    if let current = try await provider.snapshot(source), !current.isPlaying {
                        do {
                            try await provider.perform(.playPause, expected: current, token: NowPlayingActionToken())
                            lines.append("\(source.rawValue): resume succeeded")
                        } catch { lines.append("\(source.rawValue): resume failed: \(error)") }
                    }
                    if let current = try await provider.snapshot(source), current.isPlaying {
                        do {
                            try await provider.perform(.next, expected: current, token: NowPlayingActionToken())
                            try await Task.sleep(for: .milliseconds(600))
                            if let next = try await provider.snapshot(source) {
                                let changed = next.title != current.title || next.artist != current.artist
                                lines.append("\(source.rawValue): next changed track=\(changed)")
                                if changed {
                                    try await provider.perform(.previous, expected: next, token: NowPlayingActionToken())
                                    try await Task.sleep(for: .milliseconds(600))
                                    if let restored = try await provider.snapshot(source) {
                                        lines.append("\(source.rawValue): previous restored track=\(restored.title == current.title && restored.artist == current.artist)")
                                    }
                                }
                            }
                        } catch { lines.append("\(source.rawValue): skip failed: \(error)") }
                    }
                } catch { lines.append("\(source.rawValue): snapshot failed: \(error)") }
            }
            try? lines.joined(separator: "\n").write(to: URL(fileURLWithPath: "/tmp/Brim-music-diagnostic.txt"), atomically: true, encoding: .utf8)
            app.terminate(nil)
        }
        app.run()
        exit(0)
    }
    let delegate = AppDelegate()
    app.delegate = delegate

    // No Dock icon / app switcher entry — Brim lives entirely in the menu bar.
    app.setActivationPolicy(.accessory)

    app.run()
}
