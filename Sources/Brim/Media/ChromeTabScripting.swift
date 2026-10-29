import AppKit
import Carbon

/// Runs page JavaScript in Chrome's music.youtube.com tabs, one result per line, by sending Apple
/// Events to each Chrome process by PID. A `tell application id "com.google.Chrome"` script reaches
/// only one instance when several run (an automation Chrome beside the user's): it then found no
/// YouTube Music tab, so the queue fell back to accessibility and Play next failed (seen live).
enum ChromeTabScripting {
    private static let queue = DispatchQueue(label: "brim.chrome-tabs", qos: .userInitiated)
    /// Per event; the queue scripts answer in well under a second.
    static let eventTimeout: TimeInterval = 8

    static func run(_ javaScript: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { continuation.resume(with: Result { try runNow(javaScript) }) }
        }
    }

    /// The first Chrome (oldest first: the user's own) whose YouTube Music tabs answer. Stopping
    /// there means a click script never runs twice. Throws only when no instance answered.
    private static func runNow(_ javaScript: String) throws -> String {
        let chromes = NSRunningApplication.runningApplications(withBundleIdentifier: NowPlayingSource.youtubeChrome.bundleID)
            .filter { !$0.isTerminated }
            .sorted { ($0.launchDate ?? .distantPast) < ($1.launchDate ?? .distantPast) }
        guard !chromes.isEmpty else { throw NowPlayingFailure.notRunning(NowPlayingSource.youtubeChrome.name) }
        var failure: Error?
        for chrome in chromes {
            let target = NSAppleEventDescriptor(processIdentifier: chrome.processIdentifier)
            do {
                let lines = try musicTabs(target).compactMap { tab -> String? in
                    let reply = try send(target, "CrSu", "ExJa", ["----": tab, "JvSc": NSAppleEventDescriptor(string: javaScript)])
                    return reply.stringValue.flatMap { $0.isEmpty ? nil : $0 }
                }
                if !lines.isEmpty { return lines.joined(separator: "\n") }
            } catch {
                failure = failure ?? error
            }
        }
        if let failure { throw failure }
        return ""
    }

    private static func musicTabs(_ target: NSAppleEventDescriptor) throws -> [NSAppleEventDescriptor] {
        let windows = try send(target, "core", "getd", ["----": NowPlayingBrowser.all("cwin")])
        guard windows.numberOfItems > 0 else { return [] }
        var result: [NSAppleEventDescriptor] = []
        for index in 1...min(windows.numberOfItems, 20) {
            guard let window = windows.atIndex(index) else { continue }
            let tabs = try send(target, "core", "getd", ["----": NowPlayingBrowser.all("CrTb", in: window)])
            guard tabs.numberOfItems > 0 else { continue }
            let urls = try send(target, "core", "getd", ["----": NowPlayingAppleEvents.property("URL ", of: NowPlayingBrowser.all("CrTb", in: window))])
            for tabIndex in 1...min(tabs.numberOfItems, 200) {
                guard let tab = tabs.atIndex(tabIndex), let url = URL(string: urls.atIndex(tabIndex)?.stringValue ?? ""),
                      url.scheme == "https", url.host == "music.youtube.com" else { continue }
                result.append(tab)
            }
        }
        return result
    }

    /// Chrome's own error text is kept (its "Allow JavaScript from Apple Events" message drives the
    /// hint in Playing Next).
    private static func send(_ target: NSAppleEventDescriptor, _ eventClass: String, _ eventID: String,
                             _ parameters: [String: NSAppleEventDescriptor]) throws -> NSAppleEventDescriptor {
        let event = NSAppleEventDescriptor(
            eventClass: NowPlayingAppleEvents.code(eventClass), eventID: NowPlayingAppleEvents.code(eventID),
            targetDescriptor: target, returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        for (key, value) in parameters { event.setParam(value, forKeyword: NowPlayingAppleEvents.code(key)) }
        let reply: NSAppleEventDescriptor
        do {
            reply = try event.sendEvent(options: [.waitForReply, .neverInteract], timeout: eventTimeout)
        } catch {
            throw NowPlayingFailure.unavailable("Google Chrome did not respond.")
        }
        if let code = reply.paramDescriptor(forKeyword: NowPlayingAppleEvents.code("errn"))?.int32Value, code != 0 {
            if code == -1743 || code == -1744 { throw NowPlayingFailure.permission(NowPlayingSource.youtubeChrome.name) }
            let message = reply.paramDescriptor(forKeyword: NowPlayingAppleEvents.code("errs"))?.stringValue
            throw NowPlayingFailure.unavailable("Google Chrome got an error: " + (message ?? "error \(code)."))
        }
        return reply.paramDescriptor(forKeyword: NowPlayingAppleEvents.code("----")) ?? .null()
    }
}
