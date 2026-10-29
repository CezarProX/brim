import AppKit
import Combine
import CryptoKit
import ImageIO
import UniformTypeIdentifiers
import Vision

/// User-applied labels for clipboard items, shown as colored chips.
enum ClipboardTag: String, Codable, CaseIterable, Identifiable {
    case work, personal, important
    var id: String { rawValue }
    var title: String {
        switch self {
        case .work: return "Work"
        case .personal: return "Life"
        case .important: return "Urgent"
        }
    }
    var color: NSColor {
        switch self {
        case .work: return .systemRed
        case .personal: return .systemOrange
        case .important: return .systemYellow
        }
    }
}

struct ClipboardEntry: Codable, Identifiable, Equatable {
    enum Kind: String, Codable { case image, text, link, color, file }
    let id: UUID
    let date: Date
    let kind: Kind
    let text: String?
    let fingerprint: String
    let byteCount: Int
    let pixelSize: String?
    let ocrText: String?
    let isPinned: Bool
    /// Bundle identifier of the app that was frontmost when the copy happened.
    let sourceApp: String?
    let tag: ClipboardTag?
    /// Hides the preview until hovered, for content you don't want on screen.
    let isBlurred: Bool
    /// How many times this same content has been copied.
    let copies: Int

    init(id: UUID, date: Date, kind: Kind, text: String?, fingerprint: String,
         byteCount: Int, pixelSize: String?, ocrText: String? = nil, isPinned: Bool = false,
         sourceApp: String? = nil, tag: ClipboardTag? = nil, isBlurred: Bool = false, copies: Int = 1) {
        self.id = id
        self.date = date
        self.kind = kind
        self.text = text
        self.fingerprint = fingerprint
        self.byteCount = byteCount
        self.pixelSize = pixelSize
        self.ocrText = ocrText
        self.isPinned = isPinned
        self.sourceApp = sourceApp
        self.tag = tag
        self.isBlurred = isBlurred
        self.copies = max(1, copies)
    }

    private enum CodingKeys: String, CodingKey {
        case id, date, kind, text, fingerprint, byteCount, pixelSize, ocrText, isPinned, sourceApp, tag, isBlurred, copies
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        date = try values.decode(Date.self, forKey: .date)
        kind = try values.decode(Kind.self, forKey: .kind)
        text = try values.decodeIfPresent(String.self, forKey: .text)
        fingerprint = try values.decode(String.self, forKey: .fingerprint)
        byteCount = try values.decode(Int.self, forKey: .byteCount)
        pixelSize = try values.decodeIfPresent(String.self, forKey: .pixelSize)
        ocrText = try values.decodeIfPresent(String.self, forKey: .ocrText)
        isPinned = try values.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        sourceApp = try values.decodeIfPresent(String.self, forKey: .sourceApp)
        tag = try? values.decodeIfPresent(ClipboardTag.self, forKey: .tag)
        isBlurred = try values.decodeIfPresent(Bool.self, forKey: .isBlurred) ?? false
        copies = max(1, try values.decodeIfPresent(Int.self, forKey: .copies) ?? 1)
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(date, forKey: .date)
        try values.encode(kind, forKey: .kind)
        try values.encodeIfPresent(text, forKey: .text)
        try values.encode(fingerprint, forKey: .fingerprint)
        try values.encode(byteCount, forKey: .byteCount)
        try values.encodeIfPresent(pixelSize, forKey: .pixelSize)
        try values.encodeIfPresent(ocrText, forKey: .ocrText)
        if isPinned { try values.encode(true, forKey: .isPinned) }
        try values.encodeIfPresent(sourceApp, forKey: .sourceApp)
        try values.encodeIfPresent(tag, forKey: .tag)
        if isBlurred { try values.encode(true, forKey: .isBlurred) }
        if copies > 1 { try values.encode(copies, forKey: .copies) }
    }

    func withPinned(_ value: Bool) -> ClipboardEntry { updating(pinned: value) }

    /// Returns a copy with the given fields replaced; the original is never mutated.
    func updating(pinned: Bool? = nil, tag: ClipboardTag?? = nil, blurred: Bool? = nil,
                  text newText: String? = nil, kind newKind: Kind? = nil,
                  fingerprint newFingerprint: String? = nil, byteCount newByteCount: Int? = nil) -> ClipboardEntry {
        ClipboardEntry(id: id, date: date, kind: newKind ?? kind, text: newText ?? text,
                       fingerprint: newFingerprint ?? fingerprint, byteCount: newByteCount ?? byteCount,
                       pixelSize: pixelSize, ocrText: ocrText, isPinned: pinned ?? isPinned,
                       sourceApp: sourceApp, tag: tag ?? self.tag, isBlurred: blurred ?? isBlurred,
                       copies: copies)
    }

    var title: String {
        switch kind {
        case .image: return "Copied image"
        case .file: return fileURLs.map(\.lastPathComponent).joined(separator: ", ")
        default: return String((text ?? "").prefix(300))
        }
    }

    /// Files for a `.file` entry, one path per line of `text`.
    var fileURLs: [URL] {
        guard kind == .file, let text else { return [] }
        return text.split(separator: "\n").map { URL(fileURLWithPath: String($0)).standardizedFileURL }
    }

    static func webURL(_ text: String) -> URL? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.contains(where: \.isWhitespace), let url = URL(string: value),
              ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil else { return nil }
        return url
    }

    /// Parses #RGB, #RRGGBB, #RRGGBBAA (with or without #) and rgb()/rgba() text as a color.
    static func color(from text: String) -> NSColor? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard value.count <= 40 else { return nil }
        if value.range(of: #"^#?([0-9a-f]{3}|[0-9a-f]{6}|[0-9a-f]{8})$"#, options: .regularExpression) != nil {
            var hex = value.hasPrefix("#") ? String(value.dropFirst()) : value
            if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
            guard let number = UInt64(hex, radix: 16) else { return nil }
            let hasAlpha = hex.count == 8
            let shifted = hasAlpha ? number >> 8 : number
            return NSColor(srgbRed: CGFloat((shifted >> 16) & 0xff) / 255, green: CGFloat((shifted >> 8) & 0xff) / 255,
                           blue: CGFloat(shifted & 0xff) / 255, alpha: hasAlpha ? CGFloat(number & 0xff) / 255 : 1)
        }
        let pattern = #"^rgba?\(\s*(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(\d{1,3})\s*(,\s*(0|1|0?\.\d+)\s*)?\)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) else { return nil }
        func component(_ index: Int) -> Int? {
            Range(match.range(at: index), in: value).flatMap { Int(value[$0]) }
        }
        guard let red = component(1), let green = component(2), let blue = component(3),
              [red, green, blue].allSatisfy({ (0...255).contains($0) }) else { return nil }
        let alpha = Range(match.range(at: 5), in: value).flatMap { Double(value[$0]) } ?? 1
        return NSColor(srgbRed: CGFloat(red) / 255, green: CGFloat(green) / 255, blue: CGFloat(blue) / 255, alpha: alpha)
    }

    static func hex(_ color: NSColor) -> String? {
        guard let rgb = color.usingColorSpace(.sRGB) else { return nil }
        return String(format: "#%02X%02X%02X", Int((rgb.redComponent * 255).rounded()),
                      Int((rgb.greenComponent * 255).rounded()), Int((rgb.blueComponent * 255).rounded()))
    }
}

/// Local clipboard history. Only observes copies made after monitoring starts.
/// Respect confidential/transient markers before asking a pasteboard for content.
@MainActor
final class ClipboardStore: ObservableObject {
    /// History writes are coalesced for 1.5 s on the live store; quit flushes them.
    static let shared = ClipboardStore(saveDelay: 1.5)
    @Published private(set) var entries: [ClipboardEntry] = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var isMonitoring = false

    private let directory: URL
    let pasteboard: NSPasteboard
    private let maxCount: Int
    private let maxBytes: Int
    private let maxTextBytes: Int
    private let maxImageBytes = 16 * 1024 * 1024
    private let files = FileManager.default
    private let recognizeText: @Sendable (CGImage) -> String?
    private let frontmostApp: @MainActor () -> String?
    private let settings: AppSettings
    private let autoClear = ClipboardAutoClear()
    /// Current privacy and retention rules, read fresh from settings on every use.
    var policy: ClipboardPolicy { ClipboardPolicy(settings: settings) }
    private var effectiveLimit: Int { min(maxCount, policy.limit ?? maxCount) }
    private var timer: Timer?
    private var lastChange: Int
    private var generation = 0
    private var isReading = false
    private let readTimeout: TimeInterval
    private let readSnapshot: @Sendable (ClipboardPasteboardBox) -> ClipboardSnapshot?
    /// Seconds to coalesce history writes; 0 writes immediately (tests, imports at launch).
    private let saveDelay: TimeInterval
    private var pendingSave: [ClipboardEntry]?
    private var saveTask: Task<Void, Never>?
    /// How many times history was actually written to disk.
    private(set) var saveCount = 0
    private var thumbnails: [UUID: NSImage] = [:]
    private var metadataURL: URL { directory.appendingPathComponent("entries.json") }
    private var maxMetadataBytes: Int {
        let ceiling = 100 * 1024 * 1024
        // A control character occupies one UTF-8 byte but six JSON bytes (for example \\u0001).
        let escaped = maxTextBytes.multipliedReportingOverflow(by: 6)
        guard !escaped.overflow else { return ceiling }
        let item = escaped.partialValue.addingReportingOverflow(2048)
        guard !item.overflow else { return ceiling }
        let total = item.partialValue.multipliedReportingOverflow(by: maxCount)
        guard !total.overflow else { return ceiling }
        return min(ceiling, total.partialValue)
    }

    init(directory: URL? = nil, pasteboard: NSPasteboard = .general,
         maxCount: Int = 100_000, maxBytes: Int = 100 * 1024 * 1024, maxTextBytes: Int = 100_000,
         recognizeText: @escaping @Sendable (CGImage) -> String? = { ClipboardOCR.recognize($0) },
         settings: AppSettings = .shared,
         saveDelay: TimeInterval = 0,
         readTimeout: TimeInterval = 3,
         readSnapshot: (@Sendable (ClipboardPasteboardBox) -> ClipboardSnapshot?)? = nil,
         frontmostApp: @escaping @MainActor () -> String? = {
             NSWorkspace.shared.frontmostApplication?.bundleIdentifier
         }) {
        self.frontmostApp = frontmostApp
        self.settings = settings
        self.saveDelay = saveDelay
        self.readTimeout = readTimeout
        let reader = ClipboardSnapshotReader(maxImageBytes: 16 * 1024 * 1024, maxTextBytes: max(1, maxTextBytes))
        self.readSnapshot = readSnapshot ?? { reader.read($0) }
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Brim/Clipboard", isDirectory: true)
        self.pasteboard = pasteboard
        self.maxCount = max(1, maxCount)
        self.maxBytes = max(1, maxBytes)
        self.maxTextBytes = max(1, maxTextBytes)
        self.recognizeText = recognizeText
        lastChange = pasteboard.changeCount
        do { try prepareDirectory(); try load() } catch {
            report(error)
            preserveUnreadableHistory()
        }
    }

    /// A history file that can't be read is set aside, not overwritten by the next copy, so a
    /// decoding bug or a partial write never silently erases the user's clipboard history.
    private func preserveUnreadableHistory() {
        guard files.fileExists(atPath: metadataURL.path) else { return }
        let stamp = Int(Date().timeIntervalSince1970)
        let backup = metadataURL.deletingLastPathComponent()
            .appendingPathComponent("\(metadataURL.deletingPathExtension().lastPathComponent)-unreadable-\(stamp).json")
        do { try files.moveItem(at: metadataURL, to: backup) } catch { report(error) }
        // Its images are still referenced by the set-aside index; don't sweep them as orphans.
        keepsOrphanedImages = true
    }

    /// Set when the history index could not be read: its images stay on disk for recovery.
    private var keepsOrphanedImages = false

    func start() {
        guard timer == nil else { return }
        lastChange = pasteboard.changeCount
        isMonitoring = true
        pruneExpired()
        let timer = Timer(timeInterval: 0.8, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.captureChange() }
        }
        timer.tolerance = 0.15
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        flushPendingSave()
        timer?.invalidate()
        timer = nil
        generation += 1
        isMonitoring = false
    }

    func captureChange() async {
        guard isMonitoring, !isReading, pasteboard.changeCount != lastChange else { return }
        isReading = true
        defer { isReading = false }
        let change = pasteboard.changeCount
        lastChange = change
        let types = ((pasteboard.types ?? []) + (pasteboard.pasteboardItems ?? []).flatMap(\.types)).map(\.rawValue)
        let frontmost = frontmostApp()
        scheduleAutoClear(change: change, sensitive: ClipboardPolicy.isSensitive(types: types, frontmost: frontmost))
        guard !policy.shouldSkip(types: types, frontmost: frontmost) else { return }
        let currentGeneration = generation
        let source = frontmost.flatMap { $0 == Bundle.main.bundleIdentifier ? nil : $0 }
        // Sources may hand content over lazily, so the read happens off the main thread with a
        // timeout; the main actor only ever sees the finished, size-bounded snapshot.
        let box = ClipboardPasteboardBox(pasteboard: pasteboard)
        let read = readSnapshot
        guard let snapshot = await ClipboardSnapshotReader.run(timeout: readTimeout, { read(box) }),
              pasteboard.changeCount == change, generation == currentGeneration else { return }
        do {
            switch snapshot {
            case .files(let paths):
                try add(kind: .file, text: paths, image: nil, source: source)
            case .image(let data):
                let recognizeText = recognizeText
                let maxTextBytes = maxTextBytes
                let prepared = try await Task.detached(priority: .utility) {
                    try ClipboardImage.prepare(data, recognizeText: recognizeText, maxTextBytes: maxTextBytes)
                }.value
                guard generation == currentGeneration else { return }
                try add(kind: .image, text: nil, image: prepared, source: source)
            case .color(let hex):
                try add(kind: .color, text: hex, image: nil, source: source)
            case .text(let text):
                try add(kind: Self.kind(of: text), text: text, image: nil, source: source)
            }
        } catch { report(error) }
    }

    /// Whether a copy carrying these pasteboard types is kept out of history under default privacy settings.
    static func shouldIgnore(_ types: [String]) -> Bool {
        ClipboardPolicy().shouldSkip(types: types, frontmost: nil)
    }

    private func scheduleAutoClear(change: Int, sensitive: Bool) {
        let seconds = settings.clipboardAutoClearSeconds
        guard ClipboardAutoClear.shouldSchedule(seconds: seconds, onlySensitive: settings.clipboardAutoClearOnlySensitive,
                                                sensitive: sensitive) else { autoClear.cancel(); return }
        autoClear.schedule(pasteboard: pasteboard, changeCount: change, seconds: seconds) { [weak self] newCount in
            self?.lastChange = newCount
        }
    }

    /// Records our own pasteboard write so the monitor ignores it, and arms the auto-clear timer.
    func didWritePasteboard() {
        lastChange = pasteboard.changeCount
        scheduleAutoClear(change: lastChange, sensitive: false)
    }

    @discardableResult
    func copy(_ entry: ClipboardEntry) -> Bool {
        guard entries.contains(where: { $0.id == entry.id }) else { return false }
        if entry.kind == .file {
            let urls = entry.fileURLs.filter { files.fileExists(atPath: $0.path) }
            guard !urls.isEmpty else { return false }
            pasteboard.clearContents()
            let result = pasteboard.writeObjects(urls.map { $0 as NSURL })
            pasteboard.setData(Data(), forType: .init("io.github.cezarprox.brim.clipboard-replay"))
            didWritePasteboard()
            return result
        }
        let item = NSPasteboardItem()
        if let stored = entry.text {
            let text = entry.kind == .link && policy.cleanLinksOnCopy ? ClipboardLinkCleaner.clean(stored) : stored
            item.setString(text, forType: .string)
            if entry.kind == .link, let url = ClipboardEntry.webURL(text) { item.setString(url.absoluteString, forType: .URL) }
        } else {
            guard let data = imageData(for: entry) else { return false }
            item.setData(data, forType: .png)
        }
        item.setData(Data(), forType: .init("io.github.cezarprox.brim.clipboard-replay"))
        pasteboard.clearContents()
        let result = pasteboard.writeObjects([item])
        didWritePasteboard()
        return result
    }

    @discardableResult
    func copyRecognizedText(_ entry: ClipboardEntry) -> Bool {
        guard entries.contains(where: { $0.id == entry.id }),
              let text = entry.ocrText, !text.isEmpty else { return false }
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        item.setData(Data(), forType: .init("io.github.cezarprox.brim.clipboard-replay"))
        pasteboard.clearContents()
        let result = pasteboard.writeObjects([item])
        didWritePasteboard()
        return result
    }

    @discardableResult
    func setPinned(_ entry: ClipboardEntry, _ pinned: Bool) -> Bool {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return false }
        guard entries[index].isPinned != pinned else { return true }
        var changed = entries
        changed[index] = changed[index].withPinned(pinned)
        update(bounded(changed))
        return entries.first(where: { $0.id == entry.id })?.isPinned == pinned
    }

    @discardableResult
    func setTag(_ entry: ClipboardEntry, _ tag: ClipboardTag?) -> Bool {
        replace(entry) { $0.updating(tag: .some(tag)) }
    }

    @discardableResult
    func setBlurred(_ entry: ClipboardEntry, _ blurred: Bool) -> Bool {
        replace(entry) { $0.updating(blurred: blurred) }
    }

    /// Rewrites a text entry in place, keeping its identity, pin and tag.
    @discardableResult
    func edit(_ entry: ClipboardEntry, text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard entry.kind != .image, entry.kind != .file, !trimmed.isEmpty,
              text.utf8.count <= maxTextBytes else { return false }
        let fingerprint = SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
        return replace(entry) {
            $0.updating(text: text, kind: Self.kind(of: text), fingerprint: fingerprint,
                        byteCount: text.utf8.count)
        }
    }

    private func replace(_ entry: ClipboardEntry, _ change: (ClipboardEntry) -> ClipboardEntry) -> Bool {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return false }
        var changed = entries
        changed[index] = change(changed[index])
        update(bounded(changed))
        return entries.contains { $0 == changed[index] }
    }

    static func kind(of text: String) -> ClipboardEntry.Kind {
        if ClipboardEntry.color(from: text) != nil { return .color }
        return ClipboardEntry.webURL(text) == nil ? .text : .link
    }

    func imageData(for entry: ClipboardEntry) -> Data? {
        guard entry.kind == .image else { return nil }
        do { return try Data(contentsOf: imageURL(entry.id)) } catch { report(error); return nil }
    }

    func thumbnail(for entry: ClipboardEntry) -> NSImage? {
        if let image = thumbnails[entry.id] { return image }
        // Called during SwiftUI rendering: never publish an error here.
        let image = NSImage(contentsOf: thumbnailURL(entry.id))
        thumbnails[entry.id] = image
        return image
    }

    func remove(_ entry: ClipboardEntry) { update(entries.filter { $0.id != entry.id }) }
    func clearUnpinned() { update(entries.filter(\.isPinned)) }
    func clear() { update([]) }

    private func add(kind: ClipboardEntry.Kind, text rawText: String?, image: ClipboardImage?, source: String? = nil) throws {
        let policy = policy
        let text = kind == .link && policy.cleanLinksOnCapture ? rawText.map(ClipboardLinkCleaner.clean) : rawText
        let content = image?.png ?? Data((text ?? "").utf8)
        let fingerprint = SHA256.hash(data: content).map { String(format: "%02x", $0) }.joined()
        let previous = policy.rejectDuplicates ? entries.first { $0.kind == kind && $0.fingerprint == fingerprint } : nil
        let count = content.count + (image?.thumbnail.count ?? 0)
        guard count <= maxBytes else { throw ClipboardError.tooLarge }
        let entry = ClipboardEntry(id: previous?.id ?? UUID(), date: Date(), kind: kind, text: text,
                                   fingerprint: fingerprint, byteCount: count, pixelSize: image?.pixelSize,
                                   ocrText: image?.ocrText ?? previous?.ocrText,
                                   isPinned: previous?.isPinned ?? false,
                                   sourceApp: source ?? previous?.sourceApp, tag: previous?.tag,
                                   isBlurred: previous?.isBlurred ?? false,
                                   copies: (previous?.copies ?? 0) + 1)
        let updated = bounded([entry] + entries.filter { $0.id != entry.id })
        do {
            if previous == nil, let image {
                try write(image.png, to: imageURL(entry.id))
                try write(image.thumbnail, to: thumbnailURL(entry.id))
            }
            try persist(updated)
        } catch {
            if previous == nil { try? removeImages(entry.id) }
            throw error
        }
        entries = updated
        errorMessage = nil
        try cleanUnusedFiles()
    }

    private func update(_ updated: [ClipboardEntry]) {
        generation += 1
        do {
            try persist(updated)
            entries = updated
            errorMessage = nil
            try cleanUnusedFiles()
        } catch { report(error) }
    }

    private func load() throws {
        guard files.fileExists(atPath: metadataURL.path) else { return }
        let size = (try files.attributesOfItem(atPath: metadataURL.path)[.size] as? NSNumber)?.intValue ?? 0
        guard size <= maxMetadataBytes else { throw ClipboardError.tooLarge }
        let decoded = try JSONDecoder().decode([ClipboardEntry].self, from: Data(contentsOf: metadataURL))
        var seen = Set<UUID>()
        let valid = decoded.filter { entry in
            guard seen.insert(entry.id).inserted, entry.byteCount >= 0, entry.byteCount <= maxBytes else { return false }
            guard entry.ocrText.map({ $0.utf8.count <= maxTextBytes }) ?? true,
                  entry.kind == .image || entry.ocrText == nil else { return false }
            if entry.kind == .image {
                return files.fileExists(atPath: imageURL(entry.id).path)
                    && files.fileExists(atPath: thumbnailURL(entry.id).path)
            }
            return entry.text.map { $0.utf8.count <= maxTextBytes && $0.utf8.count == entry.byteCount } ?? false
        }
        entries = bounded(valid.sorted { $0.date > $1.date })
        try writeHistory(entries)
        try cleanUnusedFiles()
    }

    private func bounded(_ candidates: [ClipboardEntry]) -> [ClipboardEntry] {
        ClipboardPolicy.retain(candidates, limit: effectiveLimit, maxBytes: maxBytes, keepFor: policy.keepFor)
    }

    /// Drops unpinned entries that outlived "Keep entries for", or exceed a lowered limit.
    func pruneExpired() {
        let pruned = bounded(entries)
        if pruned.count != entries.count { update(pruned) }
    }

    /// Honors "Clear history on quit" (pinned entries stay). Call once at termination.
    func prepareForQuit() {
        if settings.clipboardClearOnQuit { clearUnpinned() }
        flushPendingSave()
    }

    /// Adds entries imported from another app, skipping content already in history. Returns how many were added.
    @discardableResult
    func importItems(_ items: [ClipboardImportItem]) -> Int {
        var known = Set(entries.map { "\($0.kind.rawValue):\($0.fingerprint)" })
        var added: [ClipboardEntry] = []
        for item in items where item.text.utf8.count <= maxTextBytes {
            let kind = Self.kind(of: item.text)
            let fingerprint = SHA256.hash(data: Data(item.text.utf8)).map { String(format: "%02x", $0) }.joined()
            guard known.insert("\(kind.rawValue):\(fingerprint)").inserted else { continue }
            added.append(ClipboardEntry(id: UUID(), date: item.date, kind: kind, text: item.text,
                                        fingerprint: fingerprint, byteCount: item.text.utf8.count, pixelSize: nil,
                                        isPinned: item.isPinned, copies: item.copies))
        }
        guard !added.isEmpty else { return 0 }
        let merged = bounded(entries + added)
        update(merged)
        let kept = Set(merged.map(\.id))
        return added.filter { kept.contains($0.id) }.count
    }

    private func imageURL(_ id: UUID) -> URL { directory.appendingPathComponent("\(id.uuidString).png") }
    private func thumbnailURL(_ id: UUID) -> URL { directory.appendingPathComponent("\(id.uuidString)-thumb.png") }
    private func prepareDirectory() throws {
        try files.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try files.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    }
    private func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
        try files.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    /// Records the history to save. With a delay, writes within the window collapse into one.
    private func persist(_ values: [ClipboardEntry]) throws {
        guard saveDelay > 0 else { return try writeHistory(values) }
        pendingSave = values
        guard saveTask == nil else { return }
        let delay = saveDelay
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.flushPendingSave()
        }
    }

    /// Writes any history still waiting for the debounce. Safe to call anytime; quit calls it.
    func flushPendingSave() {
        saveTask?.cancel()
        saveTask = nil
        guard let values = pendingSave else { return }
        pendingSave = nil
        do { try writeHistory(values) } catch { report(error) }
    }

    private func writeHistory(_ values: [ClipboardEntry]) throws {
        saveCount += 1
        let data = try JSONEncoder().encode(values)
        guard data.count <= maxMetadataBytes else { throw ClipboardError.tooLarge }
        try write(data, to: metadataURL)
    }
    private func removeImages(_ id: UUID) throws {
        for url in [imageURL(id), thumbnailURL(id)] where files.fileExists(atPath: url.path) { try files.removeItem(at: url) }
    }
    private func cleanUnusedFiles() throws {
        guard !keepsOrphanedImages else { return }
        let retained = Set(entries.map(\.id))
        thumbnails = thumbnails.filter { retained.contains($0.key) }
        for url in try files.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) where url.pathExtension == "png" {
            let name = url.deletingPathExtension().lastPathComponent
            let raw = name.hasSuffix("-thumb") ? String(name.dropLast(6)) : name
            if let id = UUID(uuidString: raw), !retained.contains(id) { try files.removeItem(at: url) }
        }
    }
    private func report(_ error: Error) { errorMessage = "Couldn’t update clipboard history. \(error.localizedDescription)" }
}

private enum ClipboardError: LocalizedError {
    case invalidImage, tooLarge
    var errorDescription: String? {
        switch self {
        case .invalidImage: return "This image could not be read."
        case .tooLarge: return "This item exceeds the history size limit."
        }
    }
}

private struct ClipboardImage: Sendable {
    let png: Data
    let thumbnail: Data
    let pixelSize: String
    let ocrText: String?

    static func prepare(_ data: Data, recognizeText: @Sendable (CGImage) -> String?, maxTextBytes: Int) throws -> Self {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 16_000, height <= 16_000,
              width * height <= 40_000_000,
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let small = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 360,
                kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary) else { throw ClipboardError.invalidImage }
        let png = try encode(image)
        guard png.count <= 16 * 1024 * 1024 else { throw ClipboardError.tooLarge }
        let recognized = recognizeText(image).flatMap { ClipboardOCR.bounded($0, maxBytes: maxTextBytes) }
        return Self(png: png, thumbnail: try encode(small), pixelSize: "\(width) × \(height)", ocrText: recognized)
    }

    private static func encode(_ image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw ClipboardError.invalidImage
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw ClipboardError.invalidImage }
        return data as Data
    }
}

enum ClipboardOCR {
    static func recognize(_ image: CGImage) -> String? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        do { try VNImageRequestHandler(cgImage: image).perform([request]) }
        catch { return nil }
        let text = (request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        return text.isEmpty ? nil : text
    }

    static func bounded(_ text: String, maxBytes: Int) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.utf8.count <= maxBytes { return trimmed }
        var result = ""
        var byteCount = 0
        result.reserveCapacity(min(trimmed.count, maxBytes))
        for character in trimmed {
            let characterBytes = String(character).utf8.count
            let nextCount = byteCount + characterBytes
            guard nextCount <= maxBytes else { break }
            result.append(character)
            byteCount = nextCount
        }
        return result.isEmpty ? nil : result
    }
}
