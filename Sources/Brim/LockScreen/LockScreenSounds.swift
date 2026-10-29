import AppKit

/// The system sounds offered for lock and unlock. Only names that exist in `/System/Library/Sounds`
/// are ever accepted, so a stored value can never point at an arbitrary file.
enum LockScreenSounds {
    /// Stored when the user picks "None".
    static let none = "None"
    static let directory = URL(fileURLWithPath: "/System/Library/Sounds", isDirectory: true)

    private static let extensions: Set<String> = ["aiff", "aif", "wav", "caf", "mp3", "m4a"]

    static func available(in directory: URL = LockScreenSounds.directory) -> [String] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { extensions.contains($0.pathExtension.lowercased()) }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// The name itself when it names an installed sound; nil for "None", unknown names and paths.
    static func validated(_ name: String?, in directory: URL = LockScreenSounds.directory) -> String? {
        guard let name, name != none, !name.isEmpty, !name.contains("/") else { return nil }
        return available(in: directory).contains(name) ? name : nil
    }

    static func url(for name: String?, in directory: URL = LockScreenSounds.directory) -> URL? {
        guard let valid = validated(name, in: directory) else { return nil }
        let match = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil))?
            .first { $0.deletingPathExtension().lastPathComponent == valid }
        return match
    }

    @MainActor private static var playing: NSSound?

    /// Plays the named system sound; silently does nothing for None or a missing file.
    @MainActor static func play(_ name: String?) {
        guard let url = url(for: name), let sound = NSSound(contentsOf: url, byReference: true) else { return }
        playing = sound
        sound.play()
    }
}
