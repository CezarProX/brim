import AppKit

/// Only one Brim may own the notch: a second copy (say, the installed app next to a fresh
/// build) would draw a second island on every display. The newest launch wins and asks the
/// others to quit.
enum SingleInstance {
  /// Process IDs of other running copies of this app.
  static func otherInstances(
    bundleID: String?, ownPID: pid_t, running: [(pid: pid_t, bundleID: String?)]
  ) -> [pid_t] {
    guard let bundleID else { return [] }
    return running.filter { $0.bundleID == bundleID && $0.pid != ownPID }.map(\.pid)
  }

  static func terminateOthers() {
    let own = NSRunningApplication.current
    let running = NSWorkspace.shared.runningApplications
    let others = otherInstances(
      bundleID: own.bundleIdentifier, ownPID: own.processIdentifier,
      running: running.map { ($0.processIdentifier, $0.bundleIdentifier) })
    for app in running where others.contains(app.processIdentifier) {
      app.terminate()
    }
  }
}
