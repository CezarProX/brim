import Foundation

/// Zip and extract with `/usr/bin/ditto` (and `tar` for tarballs). Cancellation terminates the child.
enum ArchiveTransforms {
  
  static func zip(_ sources: [URL], context: TransformContext) throws -> URL {
    guard let first = sources.first else { throw TransformError.failed("Nothing to zip.") }
    let name = sources.count == 1 ? first.deletingPathExtension().lastPathComponent : "Archive"
    let folder = TransformNaming.folder(for: first, policy: context.policy, downloads: context.downloads)
    let output = TransformNaming.uniqueURL(in: folder, name: name, fileExtension: "zip")
    if sources.count == 1 {
      try run("/usr/bin/ditto", ["-c", "-k", "--keepParent", first.path, output.path])
      return output
    }
    // ditto archives one source at a time, so several files are gathered under one folder
    // (cheap clones on APFS) that becomes the archive's top-level folder.
    let staging = FileManager.default.temporaryDirectory
      .appendingPathComponent("Brim-Zip-\(UUID().uuidString)", isDirectory: true)
    let bundle = staging.appendingPathComponent(name, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: staging) }
    try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
    for source in sources {
      let target = TransformNaming.uniqueURL(
        in: bundle, name: source.deletingPathExtension().lastPathComponent, fileExtension: source.pathExtension)
      try FileManager.default.copyItem(at: source, to: target)
    }
    try run("/usr/bin/ditto", ["-c", "-k", "--keepParent", bundle.path, output.path])
    return output
  }

  /// Extracts into a new folder named after the archive, never into an existing one.
  static func extract(_ source: URL, context: TransformContext) throws -> URL {
    let folder = TransformNaming.folder(for: source, policy: context.policy, downloads: context.downloads)
    let base = ArchiveFormat.folderName(for: source)
    let target = TransformNaming.uniqueURL(in: folder, name: base, fileExtension: "")
    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
    do {
      switch ArchiveFormat.extractor(forExtension: source.pathExtension) {
      case .ditto: try run("/usr/bin/ditto", ["-x", "-k", source.path, target.path])
      case .tar: try run("/usr/bin/tar", ["-xf", source.path, "-C", target.path])
      case .bsdtar: try run(ArchiveFormat.bsdtarPath, ArchiveFormat.bsdtarArguments(archive: source, into: target))
      case nil: throw TransformError.unsupported("Extracting .\(source.pathExtension)")
      }
    } catch {
      try? FileManager.default.removeItem(at: target)
      throw error
    }
    return target
  }

  private static func run(_ tool: String, _ arguments: [String]) throws {
    try ExternalProcess.run(tool, arguments, failure: "The archive tool failed.")
  }
}
