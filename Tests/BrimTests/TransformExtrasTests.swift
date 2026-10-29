import CoreGraphics
import Foundation
import Testing

@testable import Brim

struct ArchiveFormatTests {
  @Test func mapsExtensionsToExtractors() {
    #expect(ArchiveFormat.extractor(forExtension: "ZIP") == .ditto)
    #expect(ArchiveFormat.extractor(forExtension: "tgz") == .tar)
    #expect(ArchiveFormat.extractor(forExtension: "7z") == .bsdtar)
    #expect(ArchiveFormat.extractor(forExtension: "RAR") == .bsdtar)
    #expect(ArchiveFormat.extractor(forExtension: "png") == nil)
  }

  @Test func sevenZipAndRarCountAsArchivesForTransform() {
    #expect(TransformFileKind(url: URL(fileURLWithPath: "/x/a.7z")) == .archive)
    #expect(TransformFileKind(url: URL(fileURLWithPath: "/x/a.rar")) == .archive)
    #expect(TransformOperation.available(for: [URL(fileURLWithPath: "/x/a.7z")]).contains(.extract))
  }

  @Test func foldersDropDoubleExtensions() {
    #expect(ArchiveFormat.folderName(for: URL(fileURLWithPath: "/x/photos.tar.gz")) == "photos")
    #expect(ArchiveFormat.folderName(for: URL(fileURLWithPath: "/x/photos.7z")) == "photos")
  }

  @Test func extractsA7zArchiveWithBsdtar() async throws {
    try #require(FileManager.default.isExecutableFile(atPath: ArchiveFormat.bsdtarPath))
    let fixtures = try TransformFixtures()
    defer { fixtures.cleanup() }
    let source = fixtures.folder.appendingPathComponent("payload", isDirectory: true)
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    try Data("seven".utf8).write(to: source.appendingPathComponent("note.txt"))
    let archive = fixtures.folder.appendingPathComponent("bundle.7z")
    try ExternalProcess.run(
      ArchiveFormat.bsdtarPath, ["--format", "7zip", "-cf", archive.path, "-C", fixtures.folder.path, "payload"])
    let folder = try ArchiveTransforms.extract(archive, context: TransformContext(policy: TransformOutputPolicy()))
    #expect(folder.lastPathComponent == "bundle")
    let text = try String(contentsOf: folder.appendingPathComponent("payload/note.txt"), encoding: .utf8)
    #expect(text == "seven")
  }

  @Test func corruptArchivesFailCleanlyWithoutLeavingAFolder() throws {
    let fixtures = try TransformFixtures()
    defer { fixtures.cleanup() }
    let archive = fixtures.folder.appendingPathComponent("broken.rar")
    try Data("not a rar".utf8).write(to: archive)
    #expect(throws: TransformError.self) {
      try ArchiveTransforms.extract(archive, context: TransformContext(policy: TransformOutputPolicy()))
    }
    #expect(!FileManager.default.fileExists(atPath: fixtures.folder.appendingPathComponent("broken").path))
  }
}

struct OptionalToolTests {
  @Test func locatesTheFirstDirectoryWithTheTool() {
    let found = OptionalTools.locate(
      .ffmpeg, in: ["/opt/homebrew/bin", "/usr/local/bin"], isExecutable: { $0 == "/usr/local/bin/ffmpeg" })
    #expect(found?.path == "/usr/local/bin/ffmpeg")
    #expect(OptionalTools.locate(.cwebp, in: ["/a"], isExecutable: { _ in false }) == nil)
    #expect(OptionalTools.locate(.ghostscript, in: ["/a"], isExecutable: { $0 == "/a/gs" })?.lastPathComponent == "gs")
  }

  @Test func containersListFFmpegOnesOnlyWhenAvailable() {
    #expect(TransformVideoContainer.available(ffmpeg: false) == [.mp4, .mov])
    #expect(TransformVideoContainer.available(ffmpeg: true).contains(.webm))
    #expect(TransformVideoContainer.webm.fileExtension == "webm")
  }

  @Test func builtArgumentsAreWhatTheToolsExpect() {
    let input = URL(fileURLWithPath: "/in/a.mov"), output = URL(fileURLWithPath: "/out/a.webm")
    let ffmpeg = ExternalCodecs.ffmpegArguments(container: .webm, input: input, output: output)
    #expect(ffmpeg.contains("libvpx-vp9") && ffmpeg.last == output.path && ffmpeg.contains("-nostdin"))
    #expect(ExternalCodecs.ffmpegArguments(container: .mkv, input: input, output: output).contains("libx264"))
    let gs = ExternalCodecs.ghostscriptArguments(quality: .small, input: input, output: output)
    #expect(gs.contains("-dPDFSETTINGS=/screen") && gs.contains("-dSAFER") && gs.last == input.path)
    #expect(ExternalCodecs.ghostscriptSetting(.high) == "/printer")
    let web = ExternalCodecs.cwebpArguments(quality: 0.8, input: input, output: output)
    #expect(web.contains("80") && web.last == output.path)
  }

  @Test func webPEncodesThroughCwebpWhenInstalled() throws {
    try #require(OptionalTools.isAvailable(.cwebp))
    let image = TransformFixtures.noiseImage(width: 64, height: 64)
    let data = try ExternalCodecs.encodeWebP(image, quality: 0.7)
    #expect(String(decoding: data.prefix(4), as: UTF8.self) == "RIFF")
    #expect(String(decoding: data.dropFirst(8).prefix(4), as: UTF8.self) == "WEBP")
  }

  @Test func ffmpegWritesWebMWhenInstalled() async throws {
    try #require(OptionalTools.isAvailable(.ffmpeg))
    let fixtures = try TransformFixtures()
    defer { fixtures.cleanup() }
    let output = fixtures.folder.appendingPathComponent("clip.webm")
    let source = fixtures.folder.appendingPathComponent("clip.mp4")
    // A one-second synthetic clip from ffmpeg's own test source keeps the fixture tiny.
    let tool = try #require(OptionalTools.url(for: .ffmpeg))
    try ExternalProcess.run(tool.path, ["-y", "-loglevel", "error", "-f", "lavfi", "-i", "testsrc=size=64x64:rate=10:duration=1",
                                         "-pix_fmt", "yuv420p", source.path])
    try ExternalCodecs.convertVideo(source, container: .webm, to: output)
    #expect(TransformFixtures.size(output) > 0)
  }
}
