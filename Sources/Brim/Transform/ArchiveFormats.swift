import Foundation

/// Which tool unpacks which archive. macOS ships `bsdtar` (libarchive), which reads 7z, RAR and more.
enum ArchiveFormat {
  enum Extractor: Equatable { case ditto, tar, bsdtar }

  static let tarSuffixes = ["tar", "tgz", "gz", "bz2", "xz", "tbz", "txz"]
  static let libarchiveSuffixes = ["7z", "rar", "xar", "cpio", "zst", "lzma", "lz4", "lha", "lzh", "cab", "iso"]
  static let bsdtarPath = "/usr/bin/bsdtar"

  static func extractor(forExtension ext: String) -> Extractor? {
    let value = ext.lowercased()
    if value == "zip" { return .ditto }
    if tarSuffixes.contains(value) { return .tar }
    if libarchiveSuffixes.contains(value) { return .bsdtar }
    return nil
  }

  static func isExtractable(_ url: URL) -> Bool { extractor(forExtension: url.pathExtension) != nil }

  /// "photos.tar.gz" unpacks into "photos", not "photos.tar".
  static func folderName(for archive: URL) -> String {
    let stem = archive.deletingPathExtension()
    return stem.pathExtension.lowercased() == "tar" ? stem.deletingPathExtension().lastPathComponent : stem.lastPathComponent
  }

  /// libarchive arguments: extract quietly into `folder`, never keeping the archive's ownership.
  static func bsdtarArguments(archive: URL, into folder: URL) -> [String] {
    ["-x", "--no-same-owner", "-f", archive.path, "-C", folder.path]
  }
}
