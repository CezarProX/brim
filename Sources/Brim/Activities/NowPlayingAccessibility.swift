import AppKit
import os
import ApplicationServices

/// Reads the real player toolbar in the installed YouTube Music web app, including Romanian UI.
/// Discovery never prompts for Accessibility; the user grants that OS permission once.
enum NowPlayingAccessibility {
    static var isTrusted: Bool { AXIsProcessTrusted() }
    private static let controlsLog = Logger(subsystem: "io.github.cezarprox.brim", category: "controls")
    struct PlayerText {
        let role: String
        let label: String
        var url: String = ""
    }
    private struct Node {
        let element: AXUIElement
        let text: PlayerText
    }
    private struct WalkResult {
        let nodes: [Node]
        let playerBar: AXUIElement?
        let complete: Bool
        /// Web documents passed on the way, such as music.youtube.com/watch?v=….
        var webAreas: [(element: AXUIElement, url: String)] = []
    }
    /// The player bar found by the last full search, so each poll reads ~40 nodes instead of
    /// searching up to 800. The page's web area is kept too, for the playing video's URL.
    private struct CachedPlayer: @unchecked Sendable {
        let pid: pid_t
        let toolbar: AXUIElement
        let webArea: AXUIElement?
    }
    private static let cachedPlayer = OSAllocatedUnfairLock<CachedPlayer?>(initialState: nil)
    private static let previous = ["Previous", "Previous track", "Înapoi", "Anterior", "Melodia anterioară"]
    private static let next = ["Next", "Next track", "Înainte", "Următorul", "Melodia următoare"]
    private static let play = ["Play", "Redă", "Redare"]
    private static let pause = ["Pause", "Pauză", "Întrerupe", "Întrerupe redarea"]
    private static let toolbarNames = ["Player bar", "Player", "Bara playerului"]

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    static func urlString(_ value: Any) -> String? {
        if let url = value as? URL { return url.absoluteString }
        return value as? String
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        guard let position = attribute(element, kAXPositionAttribute),
              let size = attribute(element, kAXSizeAttribute),
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        let pointValue = position as! AXValue
        let sizeValue = size as! AXValue
        guard AXValueGetType(pointValue) == .cgPoint, AXValueGetType(sizeValue) == .cgSize else { return nil }
        var origin = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(pointValue, .cgPoint, &origin), AXValueGetValue(sizeValue, .cgSize, &dimensions) else { return nil }
        return CGRect(origin: origin, size: dimensions)
    }

    static func scopedClickPoint(button: CGRect, window: CGRect) -> CGPoint? {
        guard button.width >= 8, button.height >= 8, button.width <= 120, button.height <= 120,
              window.contains(button), button.origin.x.isFinite, button.origin.y.isFinite else { return nil }
        return CGPoint(x: button.midX, y: button.midY)
    }

    private static func clickPlayerButton(_ button: AXUIElement, in window: AXUIElement) throws {
        guard let buttonFrame = frame(of: button), let windowFrame = frame(of: window),
              let target = scopedClickPoint(button: buttonFrame, window: windowFrame),
              let source = CGEventSource(stateID: .combinedSessionState),
              let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown,
                                 mouseCursorPosition: target, mouseButton: .left),
              let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp,
                               mouseCursorPosition: target, mouseButton: .left) else {
            throw NowPlayingFailure.unavailable("YouTube Music could not locate its player button.")
        }
        let originalPointer = CGEvent(source: nil)?.location
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        if let originalPointer,
           let restore = CGEvent(mouseEventSource: source, mouseType: .mouseMoved,
                                 mouseCursorPosition: originalPointer, mouseButton: .left) {
            restore.post(tap: .cghidEventTap)
        }
    }

    private static func walk(_ root: AXUIElement, findToolbar: Bool) -> WalkResult {
        let deadline = Date().addingTimeInterval(findToolbar ? 1.4 : 0.8)
        let limit = findToolbar ? 800 : 180
        let keys = [kAXRoleAttribute, kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute, kAXURLAttribute, kAXChildrenAttribute]
        var nodes: [Node] = []
        var webAreas: [(element: AXUIElement, url: String)] = []
        var pending: [(AXUIElement, Int)] = [(root, 0)]
        var clipped = false
        while !pending.isEmpty, nodes.count < limit, Date() < deadline {
            guard let (element, depth) = pending.popLast() else { break }
            var raw: CFArray?
            guard AXUIElementCopyMultipleAttributeValues(element, keys as CFArray, [], &raw) == .success,
                  let values = raw as? [Any], values.count == keys.count else { clipped = true; continue }
            let role = values[0] as? String ?? ""
            let label = [values[1], values[2], values[3]].compactMap { $0 as? String }.first { !$0.isEmpty } ?? ""
            let url = urlString(values[4]) ?? ""
            if role == "AXWebArea", !url.isEmpty { webAreas.append((element, url)) }
            if findToolbar && role == kAXToolbarRole && toolbarNames.contains(label) {
                return WalkResult(nodes: [], playerBar: element, complete: true, webAreas: webAreas)
            }
            // Since September 2026 the bar is an unnamed group around "PLAYBACK_CONTROLS".
            if findToolbar && role == kAXGroupRole && label == "PLAYBACK_CONTROLS",
               let parent = attribute(element, kAXParentAttribute), CFGetTypeID(parent) == AXUIElementGetTypeID() {
                return WalkResult(nodes: [], playerBar: (parent as! AXUIElement), complete: true, webAreas: webAreas)
            }
            nodes.append(Node(element: element, text: PlayerText(role: role, label: label, url: url)))
            let children = values[5] as? [AXUIElement] ?? []
            guard depth < 24 else { clipped = clipped || !children.isEmpty; continue }
            clipped = clipped || children.count > 150
            // Search the end of the web view first; inside the toolbar preserve document order.
            let ordered = Array(children.prefix(150))
            let traversal = findToolbar ? ordered : Array(ordered.reversed())
            for child in traversal { pending.append((child, depth + 1)) }
        }
        return WalkResult(nodes: nodes, playerBar: nil, complete: pending.isEmpty && !clipped, webAreas: webAreas)
    }

    private static func read(requireComplete: Bool = false, in window: AXUIElement? = nil) throws -> [Node] {
        try readPlayer(requireComplete: requireComplete, in: window).nodes
    }

    private static func readReady(in window: AXUIElement, token: NowPlayingActionToken) async throws -> [Node] {
        for attempt in 0..<3 {
            guard token.isValid else { throw CancellationError() }
            do { return try read(requireComplete: true, in: window) }
            catch let failure as NowPlayingFailure {
                guard case .unavailable(let message) = failure,
                      message == "The YouTube Music player is busy. Try the control again.",
                      attempt < 2 else { throw failure }
                try await Task.sleep(for: .milliseconds(80))
            }
        }
        throw NowPlayingFailure.unavailable("The YouTube Music player is busy. Try the control again.")
    }

    /// The player bar's nodes plus the URL of the page that is playing.
    private static func readPlayer(requireComplete: Bool = false, in window: AXUIElement? = nil) throws
        -> (nodes: [Node], pageURL: String?)
    {
        guard isTrusted else { throw NowPlayingFailure.accessibility }
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: NowPlayingSource.youtubeApp.bundleID).first else {
            throw NowPlayingFailure.notRunning(NowPlayingSource.youtubeApp.name)
        }
        let pid = app.processIdentifier
        let application = AXUIElementCreateApplication(pid)
        requestFullTree(application, pid: pid)
        if window == nil, let cached = cachedPlayer.withLock({ $0 }), cached.pid == pid {
            AXUIElementSetMessagingTimeout(cached.toolbar, 0.1)
            let result = walk(cached.toolbar, findToolbar: false)
            if result.nodes.first?.text.role == kAXToolbarRole
                || result.nodes.contains(where: { $0.text.label == "PLAYBACK_CONTROLS" }) {
                guard !requireComplete || result.complete else {
                    throw NowPlayingFailure.unavailable("The YouTube Music player is busy. Try the control again.")
                }
                let pageURL = cached.webArea.flatMap { attribute($0, kAXURLAttribute) }.flatMap(urlString)
                return (result.nodes, pageURL.flatMap(watchPage))
            }
            cachedPlayer.withLock { $0 = nil }
        }
        let root = window ?? application
        AXUIElementSetMessagingTimeout(root, 0.1)
        let search = walk(root, findToolbar: true)
        guard let toolbar = search.playerBar else { return ([], nil) }
        let result = walk(toolbar, findToolbar: false)
        guard !requireComplete || result.complete else {
            throw NowPlayingFailure.unavailable("The YouTube Music player is busy. Try the control again.")
        }
        let page = playingPageIndex(search.webAreas.map(\.url)).map { search.webAreas[$0] }
        if window == nil {
            cachedPlayer.withLock { $0 = CachedPlayer(pid: pid, toolbar: toolbar, webArea: page?.element) }
        }
        return (result.nodes, page.flatMap { watchPage($0.url) })
    }

    /// The YouTube Music document, chosen by host rather than by its current URL: the player can be
    /// found on Home or with the song page minimized, and the cached area must still report the
    /// watch page once it opens, or the song never gets a cover or a resume link.
    static func playingPageIndex(_ urls: [String]) -> Int? {
        urls.firstIndex { YouTubeThumbnail.videoID(from: $0) != nil }
            ?? urls.firstIndex { URL(string: $0)?.host == "music.youtube.com" }
    }

    private static func watchPage(_ url: String) -> String? {
        YouTubeThumbnail.videoID(from: url) != nil ? url : nil
    }

    /// Read-only survey for `--music-status`: toolbars, headings and buttons the app exposes.
    static func survey() -> [String] {
        guard isTrusted, let app = NSRunningApplication.runningApplications(
            withBundleIdentifier: NowPlayingSource.youtubeApp.bundleID).first else { return ["survey: not available"] }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        requestFullTree(application, pid: app.processIdentifier)
        AXUIElementSetMessagingTimeout(application, 0.2)
        let keys = [kAXRoleAttribute, kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute,
                    kAXRoleDescriptionAttribute, kAXChildrenAttribute, kAXSubroleAttribute]
        var pending: [(AXUIElement, Int)] = [(application, 0)]
        var lines: [String] = []
        var visited = 0
        var pauseButton: AXUIElement?
        var afterPrevious = false
        let deadline = Date().addingTimeInterval(6)
        while let (element, depth) = pending.popLast(), visited < 6000, Date() < deadline {
            visited += 1
            var raw: CFArray?
            guard AXUIElementCopyMultipleAttributeValues(element, keys as CFArray, [], &raw) == .success,
                  let values = raw as? [Any], values.count == keys.count else { continue }
            let role = values[0] as? String ?? ""
            let label = [values[1], values[2], values[3]].compactMap { $0 as? String }.first { !$0.isEmpty } ?? ""
            let roleDescription = values[4] as? String ?? ""
            let subrole = values[6] as? String ?? ""
            let interesting = role == kAXToolbarRole || role == "AXHeading" || role == kAXWindowRole
                || roleDescription.lowercased().contains("toolbar") || label.lowercased().contains("player")
                || label.lowercased().contains("playerului")
                || (role == kAXButtonRole && ([play, pause, previous, next].joined().contains(label.components(separatedBy: " (").first ?? "")
                    || label.lowercased().contains("play") || label.lowercased().contains("redă")))
            // The player's play/pause button comes right after its Previous button in document order.
            if role == kAXButtonRole, (pause + play).contains(label), afterPrevious { pauseButton = element }
            if role == kAXButtonRole { afterPrevious = previous.contains(label) }
            if interesting, lines.count < 60 {
                lines.append("d\(depth) \(role)/\(subrole) [\(roleDescription)] \"\(label.prefix(50))\"")
            }
            guard depth < 40 else { continue }
            for child in (values[5] as? [AXUIElement] ?? []).prefix(200).reversed() { pending.append((child, depth + 1)) }
        }
        return ["survey visited \(visited) nodes"] + lines + ancestry(of: pauseButton)
    }

    /// The pause button's ancestors, each with the labelled nodes inside it.
    private static func ancestry(of button: AXUIElement?) -> [String] {
        guard var current = button else { return ["player: no pause button"] }
        var lines: [String] = []
        for level in 1...6 {
            guard let parentRef = attribute(current, kAXParentAttribute), CFGetTypeID(parentRef) == AXUIElementGetTypeID()
            else { break }
            current = parentRef as! AXUIElement
            let role = attribute(current, kAXRoleAttribute) as? String ?? "?"
            let label = [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute]
                .compactMap { attribute(current, $0) as? String }.first { !$0.isEmpty } ?? ""
            let nodes = walk(current, findToolbar: false).nodes.map(\.text).filter { !$0.label.isEmpty || !$0.url.isEmpty }
            lines.append("up\(level) \(role) \"\(label.prefix(40))\" labelled=\(nodes.count)")
            if level == 2 || level == 3 {
                for node in nodes.prefix(40) { lines.append("    \(node.role) \"\(node.label.prefix(55))\" \(node.url.prefix(50))") }
            }
        }
        return lines
    }

    private static let enabledPIDs = OSAllocatedUnfairLock(initialState: Set<pid_t>())

    /// Asks only the YouTube Music app for Chromium's full tree (link URLs and images).
    /// Earlier builds also set this on every Chrome process, which made Chrome keep a complete
    /// accessibility tree for every tab and slowed down typing.
    private static func requestFullTree(_ application: AXUIElement, pid: pid_t) {
        guard enabledPIDs.withLock({ $0.insert(pid).inserted }) else { return }
        AXUIElementSetAttributeValue(application, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }

    /// Clears the Chrome-wide flag earlier builds set. Called once at launch.
    static func releaseChromeFullTree() {
        // VoiceOver users need Chrome's tree; leave it alone for them.
        guard isTrusted, !NSWorkspace.shared.isVoiceOverEnabled else { return }
        for chrome in NSRunningApplication.runningApplications(withBundleIdentifier: "com.google.Chrome") {
            let element = AXUIElementCreateApplication(chrome.processIdentifier)
            AXUIElementSetMessagingTimeout(element, 0.2)
            AXUIElementSetAttributeValue(element, "AXManualAccessibility" as CFString, kCFBooleanFalse)
        }
    }

    private static func matches(_ node: PlayerText, _ labels: [String]) -> Bool {
        guard node.role == kAXButtonRole || node.role == "AXToggleButton" else { return false }
        let normalized = node.label.components(separatedBy: " (").first ?? node.label
        return labels.contains(normalized)
    }

    static func snapshot() throws -> NowPlayingSnapshot? {
        let player = try readPlayer()
        return snapshot(from: player.nodes.map(\.text), pageURL: player.pageURL)
    }

    static func snapshot(from nodes: [PlayerText], pageURL: String? = nil) -> NowPlayingSnapshot? {
        guard nodes.contains(where: { matches($0, previous) }), nodes.contains(where: { matches($0, next) }),
              nodes.contains(where: { matches($0, play + pause) }) else { return nil }
        if let redesigned = redesignedSnapshot(from: nodes, pageURL: pageURL) { return redesigned }
        // The toolbar heading names the current song. Recommendation cards never qualify.
        guard let headingIndex = nodes.firstIndex(where: { $0.role == "AXHeading" }) else { return nil }
        let heading = nodes[headingIndex].label
        let childTitle = nodes.dropFirst(headingIndex + 1).first { $0.role == kAXStaticTextRole }?.label ?? ""
        let title = heading.isEmpty ? childTitle : heading
        guard !title.isEmpty else { return nil }
        let links = nodes.filter { $0.role == "AXLink" && $0.url.contains("/channel/") }.map(\.label)
        var names: [String] = []
        for name in links where !name.isEmpty && !names.contains(name) { names.append(name) }
        // Without channel links the byline reads "Artist • Album • Year"; keep only the artist.
        let byline = nodes.dropFirst(headingIndex + 1).first {
            $0.role == kAXStaticTextRole && !$0.label.isEmpty && $0.label != title
        }?.label ?? ""
        let artistText = byline.components(separatedBy: " • ").first?
            .trimmingCharacters(in: .whitespaces) ?? ""
        let durationText = nodes.first { $0.role == kAXStaticTextRole && $0.label.contains("/") }?.label ?? ""
        let timing = parseTiming(durationText)
        let album = nodes.first { $0.role == "AXLink" && NowPlayingSnapshot.safeAlbumURL($0.url) != nil }
        let image = nodes.first { $0.role == kAXImageRole && NowPlayingSnapshot.safeArtworkURL($0.url) != nil }
        var snapshot = NowPlayingSnapshot(source: .youtubeApp, title: title,
            artist: names.isEmpty ? artistText : names.joined(separator: " · "), album: album?.label ?? "",
            duration: timing.duration, position: timing.position, isPlaying: nodes.contains { matches($0, pause) },
            // Chromium can omit the cover image even when it exposes an album link.
            // Keep the playing video's thumbnail as a reliable artwork fallback.
            artworkURL: image?.url ?? pageURL.flatMap(YouTubeThumbnail.videoID(from:))
                .flatMap(YouTubeThumbnail.artworkURL(videoID:)),
            albumURL: album?.url)
        snapshot.pageURL = pageURL.flatMap(NowPlayingResume.sanitizedPage)
        return snapshot
    }

    /// YouTube Music's 2026 player bar: the title is the first text inside "Now playing", artists are
    /// buttons up to the first " • ", and the album is the button after it.
    private static func redesignedSnapshot(from nodes: [PlayerText], pageURL: String?) -> NowPlayingSnapshot? {
        guard let start = nodes.firstIndex(where: { $0.role == kAXGroupRole && $0.label == "Now playing" }),
              let titleIndex = nodes[(start + 1)...].firstIndex(where: { $0.role == kAXStaticTextRole && !$0.label.isEmpty })
        else { return nil }
        let title = nodes[titleIndex].label
        let controls = nodes.firstIndex { $0.label == "PLAYBACK_CONTROLS" } ?? nodes.endIndex
        guard titleIndex < controls else { return nil }
        var artists: [String] = []
        var album = ""
        var pastSeparator = false
        for node in nodes[(titleIndex + 1)..<controls] {
            if node.role == kAXStaticTextRole, node.label.contains("•") { pastSeparator = true; continue }
            guard node.role == kAXButtonRole || node.role == "AXLink", !node.label.isEmpty else { continue }
            if !pastSeparator {
                if !artists.contains(node.label) { artists.append(node.label) }
            } else if album.isEmpty {
                album = node.label
            }
        }
        let durationText = nodes.first { $0.role == kAXStaticTextRole && $0.label.contains("/") }?.label ?? ""
        let timing = parseTiming(durationText)
        var snapshot = NowPlayingSnapshot(source: .youtubeApp, title: title, artist: artists.joined(separator: " · "),
            album: album, duration: timing.duration, position: timing.position,
            isPlaying: nodes.contains { matches($0, pause) },
            artworkURL: pageURL.flatMap(YouTubeThumbnail.videoID(from:)).flatMap(YouTubeThumbnail.artworkURL(videoID:)))
        snapshot.pageURL = pageURL.flatMap(NowPlayingResume.sanitizedPage)
        return snapshot
    }

    static func parseTiming(_ value: String) -> (position: TimeInterval, duration: TimeInterval) {
        func seconds(_ value: Substring) -> TimeInterval {
            let parts = value.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ":")
            guard (2...3).contains(parts.count), parts.allSatisfy({ Double($0) != nil }) else { return 0 }
            return parts.reduce(0) { $0 * 60 + (Double($1) ?? 0) }
        }
        let sides = value.split(separator: "/")
        guard sides.count == 2 else { return (0, 0) }
        return (seconds(sides[0]), seconds(sides[1]))
    }

    static func playPauseWasApplied(_ current: NowPlayingSnapshot?, expected: NowPlayingSnapshot) -> Bool {
        guard let current else { return false }
        return current.source == expected.source && current.title == expected.title
            && current.artist == expected.artist && current.isPlaying != expected.isPlaying
    }

    static func permitsScopedActivation(windowPID: pid_t, expectedPID: pid_t, isWindowMember: Bool, isRunning: Bool,
                                        isFocused: Bool, isEnabled: Bool, tokenIsValid: Bool) -> Bool {
        windowPID > 0 && windowPID == expectedPID && isWindowMember && isRunning && isFocused && isEnabled && tokenIsValid
    }

    static func sameWindowIdentity(selectedPID: pid_t, candidatePID: pid_t,
                                   selectedTitle: String, candidateTitle: String,
                                   selectedFrame: CGRect, candidateFrame: CGRect) -> Bool {
        guard selectedPID > 0, selectedPID == candidatePID, selectedTitle == candidateTitle else { return false }
        let edges = [selectedFrame.minX, selectedFrame.minY, selectedFrame.maxX, selectedFrame.maxY,
                     candidateFrame.minX, candidateFrame.minY, candidateFrame.maxX, candidateFrame.maxY]
        guard edges.allSatisfy(\.isFinite) else { return false }
        return abs(selectedFrame.minX - candidateFrame.minX) <= 1
            && abs(selectedFrame.minY - candidateFrame.minY) <= 1
            && abs(selectedFrame.maxX - candidateFrame.maxX) <= 1
            && abs(selectedFrame.maxY - candidateFrame.maxY) <= 1
    }

    private static func currentWindow(_ selected: AXUIElement, among windows: [AXUIElement], ownerPID: pid_t) -> AXUIElement? {
        var selectedPID: pid_t = 0
        guard AXUIElementGetPid(selected, &selectedPID) == .success, selectedPID == ownerPID else { return nil }
        let ownedWindows = windows.filter { candidate in
            var candidatePID: pid_t = 0
            return AXUIElementGetPid(candidate, &candidatePID) == .success && candidatePID == ownerPID
                && attribute(candidate, kAXRoleAttribute) as? String == kAXWindowRole
        }
        if ownedWindows.count == 1 { return ownedWindows[0] }
        guard let selectedFrame = frame(of: selected) else { return nil }
        let selectedTitle = attribute(selected, kAXTitleAttribute) as? String ?? ""
        let matches = ownedWindows.filter { candidate in
            guard let candidateFrame = frame(of: candidate) else { return false }
            return CFEqual(candidate, selected) || sameWindowIdentity(
                selectedPID: selectedPID, candidatePID: ownerPID,
                selectedTitle: selectedTitle,
                candidateTitle: attribute(candidate, kAXTitleAttribute) as? String ?? "",
                selectedFrame: selectedFrame, candidateFrame: candidateFrame)
        }
        return matches.count == 1 ? matches[0] : nil
    }

    private static func playerWindows(for pid: pid_t, token: NowPlayingActionToken) async throws -> [AXUIElement] {
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.1)
        for attempt in 0..<8 {
            guard token.isValid else { throw CancellationError() }
            let windows = attribute(application, kAXWindowsAttribute) as? [AXUIElement] ?? []
            if !windows.isEmpty || attempt == 7 { return windows }
            try await Task.sleep(for: .milliseconds(80))
        }
        return []
    }

    static func perform(_ command: NowPlayingCommand, expected: NowPlayingSnapshot, token: NowPlayingActionToken) async throws {
        guard isTrusted else { throw NowPlayingFailure.accessibility }
        guard token.isValid else { throw CancellationError() }
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: NowPlayingSource.youtubeApp.bundleID)
            .first(where: { !$0.isTerminated }) else {
            throw NowPlayingFailure.notRunning(NowPlayingSource.youtubeApp.name)
        }
        let ownerPID = app.processIdentifier
        let appWindows = try await playerWindows(for: ownerPID, token: token)
        guard appWindows.count <= 8 else {
            throw NowPlayingFailure.unavailable("Close extra YouTube Music windows and try again.")
        }
        // Chromium supplies remote web controls whose AXWindow may be absent or refer
        // to Chrome. Establish ownership by walking down from the shim's own windows.
        var matchingWindows: [AXUIElement] = []
        for candidate in appWindows {
            guard token.isValid else { throw CancellationError() }
            var candidatePID: pid_t = 0
            guard AXUIElementGetPid(candidate, &candidatePID) == .success, candidatePID == ownerPID,
                  attribute(candidate, kAXRoleAttribute) as? String == kAXWindowRole else { continue }
            if let current = snapshot(from: try await readReady(in: candidate, token: token).map(\.text)),
               current.title == expected.title, current.artist == expected.artist {
                matchingWindows.append(candidate)
            }
        }
        guard matchingWindows.count == 1, let window = matchingWindows.first else {
            throw NowPlayingFailure.unavailable("YouTube Music could not identify a unique player window for this song.")
        }
        let labels: [String]
        switch command {
        case .playPause: labels = play + pause
        case .next: labels = next
        case .previous: labels = previous
        case .seek: throw NowPlayingFailure.unavailable("Seeking requires the system media controls.")
        case .setFavorite, .setShuffle, .setRepeat:
            throw NowPlayingFailure.unavailable("YouTube Music doesn’t expose this control.")
        }
        let previousPID = await MainActor.run { NSWorkspace.shared.frontmostApplication?.processIdentifier }
        do {
            try await pressAndVerify(command, token: token, press: {
                try await pressInForeground(expected: expected, labels: labels,
                                            app: app, window: window, token: token)
            }, read: {
                snapshot(from: try read(in: window).map(\.text))
            })
            await restoreForeground(previousPID: previousPID, playerPID: ownerPID)
        } catch {
            await restoreForeground(previousPID: previousPID, playerPID: ownerPID)
            throw error
        }
    }

    private static func pressInForeground(expected: NowPlayingSnapshot,
                                          labels: [String], app: NSRunningApplication, window: AXUIElement,
                                          token: NowPlayingActionToken) async throws -> NowPlayingSnapshot {
        guard token.isValid else { throw CancellationError() }
        let activated = await MainActor.run {
            guard token.isValid, !app.isTerminated else { return false }
            return app.isActive || app.activate(options: [])
        }
        guard activated, token.isValid,
              AXUIElementPerformAction(window, kAXRaiseAction as CFString) == .success else {
            throw NowPlayingFailure.unavailable("YouTube Music could not bring its player window forward.")
        }
        var foreground = false
        for attempt in 0..<6 {
            guard token.isValid else { throw CancellationError() }
            foreground = await MainActor.run { NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier }
            if foreground { break }
            if attempt < 5 { try await Task.sleep(for: .milliseconds(60)) }
        }
        guard foreground else { throw NowPlayingFailure.unavailable("YouTube Music did not become active. Try the control again.") }
        // Re-read only the verified raised window; another PWA window may show the same song.
        let nodes = try await readReady(in: window, token: token)
        guard let current = snapshot(from: nodes.map(\.text)), current.title == expected.title,
              current.artist == expected.artist else {
            let seen = snapshot(from: nodes.map(\.text))
            controlsLog.error("song check failed: expected '\(expected.title, privacy: .public)' / '\(expected.artist, privacy: .public)', read '\(seen?.title ?? "nil", privacy: .public)' / '\(seen?.artist ?? "nil", privacy: .public)' nodes=\(nodes.count)")
            throw NowPlayingFailure.unavailable("The song changed. Try the control again.")
        }
        let buttons = nodes.filter { matches($0.text, labels) }
        guard buttons.count == 1, let button = buttons.first else {
            throw NowPlayingFailure.unavailable("This YouTube Music control is unavailable.")
        }
        var windowPID: pid_t = 0
        guard AXUIElementGetPid(window, &windowPID) == .success else {
            throw NowPlayingFailure.unavailable("YouTube Music could not verify the player window.")
        }
        var verifiedWindow: AXUIElement?
        for attempt in 0..<4 {
            let windows = try await playerWindows(for: app.processIdentifier, token: token)
            verifiedWindow = currentWindow(window, among: windows, ownerPID: app.processIdentifier)
            if verifiedWindow != nil { break }
            if attempt < 3 { try await Task.sleep(for: .milliseconds(80)) }
        }
        foreground = await MainActor.run { NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier }
        guard permitsScopedActivation(windowPID: windowPID, expectedPID: app.processIdentifier,
                                      isWindowMember: verifiedWindow != nil,
                                      isRunning: !app.isTerminated, isFocused: foreground,
                                      isEnabled: attribute(button.element, kAXEnabledAttribute) as? Bool == true,
                                      tokenIsValid: token.isValid) else {
            throw NowPlayingFailure.unavailable("Player focus changed. No control was sent.")
        }
        guard token.isValid else { throw CancellationError() }
        guard let verifiedWindow else { throw NowPlayingFailure.unavailable("Player focus changed. No control was sent.") }
        try clickPlayerButton(button.element, in: verifiedWindow)
        return current
    }

    /// Keep focus until the exact window receiving the action confirms its result.
    /// Never retry a toggle: a delayed first press could otherwise be undone.
    static func pressAndVerify(_ command: NowPlayingCommand, token: NowPlayingActionToken,
                               press: () async throws -> NowPlayingSnapshot,
                               read: () throws -> NowPlayingSnapshot?,
                               wait: () async throws -> Void = { try await Task.sleep(for: .milliseconds(120)) }) async throws {
        guard token.isValid else { throw CancellationError() }
        let before = try await press()
        guard case .playPause = command else {
            try await Task.sleep(for: .milliseconds(250))
            return
        }
        for _ in 0..<12 {
            try await wait()
            guard token.isValid else { throw CancellationError() }
            if playPauseWasApplied(try read(), expected: before) { return }
        }
        throw NowPlayingFailure.unavailable("YouTube Music did not change playback. Open the player and try its Play/Pause button.")
    }

    static func shouldRestoreForeground(previousPID: pid_t?, playerPID: pid_t, currentPID: pid_t?) -> Bool {
        guard let previousPID else { return false }
        return previousPID > 0 && playerPID > 0 && previousPID != playerPID && currentPID == playerPID
    }

    @MainActor
    private static func restoreForeground(previousPID: pid_t?, playerPID: pid_t) {
        guard shouldRestoreForeground(previousPID: previousPID, playerPID: playerPID,
                                      currentPID: NSWorkspace.shared.frontmostApplication?.processIdentifier),
              let previousPID, let previous = NSRunningApplication(processIdentifier: previousPID),
              !previous.isTerminated else { return }
        previous.activate(options: [])
    }
}
