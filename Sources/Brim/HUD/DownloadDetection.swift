import Foundation

/// Pure rules for spotting in-progress browser downloads and estimating the time left.
enum DownloadFileRules {
    /// Temporary extensions browsers use until a download finishes (Chrome, Safari, Firefox, others).
    static let partialExtensions: Set<String> = ["download", "crdownload", "part", "partial"]

    static func isPartial(_ name: String) -> Bool {
        !name.hasPrefix(".") && partialExtensions.contains((name as NSString).pathExtension.lowercased())
    }

    /// "Report.pdf.crdownload" -> "Report.pdf".
    static func finalName(forPartial name: String) -> String { (name as NSString).deletingPathExtension }

    static func isDiskImage(_ name: String) -> Bool { (name as NSString).pathExtension.lowercased() == "dmg" }

    /// Safari's `.download` bundle keeps the expected size in Info.plist.
    static func expectedBytes(infoPlist: Data) -> Int64? {
        guard let plist = try? PropertyListSerialization.propertyList(from: infoPlist, format: nil) as? [String: Any]
        else { return nil }
        for key in ["DownloadEntryProgressTotalToLoad", "DownloadEntryTotalBytes"] {
            if let number = plist[key] as? NSNumber, number.int64Value > 0 { return number.int64Value }
        }
        return nil
    }
}

/// Smoothed transfer rate from byte samples, and the time left when the total is known.
struct DownloadETA {
    private(set) var bytesPerSecond: Double?
    private var last: (bytes: Int64, at: Date)?
    /// Weight of the newest sample; lower is smoother.
    static let smoothing = 0.35

    mutating func add(bytes: Int64, at date: Date) {
        defer { last = (bytes, date) }
        guard let last else { return }
        let elapsed = date.timeIntervalSince(last.at)
        guard elapsed > 0.05, bytes >= last.bytes else { return }
        let instant = Double(bytes - last.bytes) / elapsed
        bytesPerSecond = bytesPerSecond.map { $0 + (instant - $0) * Self.smoothing } ?? instant
    }

    func secondsLeft(bytes: Int64, total: Int64?) -> TimeInterval? {
        guard let total, total > bytes, let rate = bytesPerSecond, rate > 1 else { return nil }
        return Double(total - bytes) / rate
    }

    static func fraction(bytes: Int64, total: Int64?) -> Double? {
        guard let total, total > 0 else { return nil }
        return min(1, max(0, Double(bytes) / Double(total)))
    }

    /// "5 sec", "3 min", "1 hr 5 min": the compact island's time-left text.
    static func format(_ seconds: TimeInterval) -> String {
        let total = max(1, Int(seconds.rounded(.up)))
        if total < 60 { return "\(total) sec" }
        if total < 3600 { return "\(Int((Double(total) / 60).rounded(.up))) min" }
        let hours = total / 3600, minutes = (total % 3600 + 59) / 60
        return minutes == 0 ? "\(hours) hr" : "\(hours) hr \(minutes) min"
    }
}

/// Decides whether a finished long task deserves a system notification.
enum LongTaskNotifyPolicy {
    static let minimumDuration: TimeInterval = 30

    static func shouldNotify(enabled: Bool, duration: TimeInterval, appIsActive: Bool) -> Bool {
        enabled && duration >= minimumDuration && !appIsActive
    }
}
