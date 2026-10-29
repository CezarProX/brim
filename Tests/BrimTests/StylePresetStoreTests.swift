import AppKit
import Testing

@testable import Brim

@MainActor
@Suite("Style presets")
struct StylePresetStoreTests {
    private let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("qs-presets-\(UUID().uuidString)/presets.json")

    private let look = CanvasStyle(
        isEnabled: true, background: .solid(RGBAColor(hex: 0x123456)), padding: 0.12, shadow: 0.3,
        corners: .large, aspect: .square, alignment: .topLeading, roundsOuterCorners: true
    )

    @Test func savedPresetsSurviveAReload() throws {
        let store = StylePresetStore(fileURL: url)
        let saved = store.save(name: "  Blog  ", style: look)
        store.save(name: "Wallpaper", style: CanvasStyle(isEnabled: true, background: .desktopWallpaper(blurred: true)))
        store.setDefault(id: saved.id)

        let reloaded = StylePresetStore(fileURL: url)
        #expect(reloaded.presets.count == 2)
        #expect(reloaded.presets[0].name == "Blog")
        #expect(reloaded.presets[0].style == look)
        #expect(reloaded.presets[1].style.background == .desktopWallpaper(blurred: true))
        #expect(reloaded.library.defaultPresetID == saved.id)
        #expect(reloaded.styleForNewCapture == look)
    }

    @Test func deletingTheDefaultClearsIt() {
        let store = StylePresetStore(fileURL: url)
        let saved = store.save(name: "A", style: look)
        store.setDefault(id: saved.id)
        store.delete(id: saved.id)
        #expect(store.presets.isEmpty)
        #expect(store.library.defaultPresetID == nil)
        #expect(StylePresetStore(fileURL: url).styleForNewCapture == nil)
    }

    @Test func unknownDefaultIsRejected() {
        let store = StylePresetStore(fileURL: url)
        store.setDefault(id: UUID())
        #expect(store.library.defaultPresetID == nil)
    }

    @Test func renameAndReplaceStylePersist() {
        let store = StylePresetStore(fileURL: url)
        let saved = store.save(name: "Old", style: .styledDefault)
        store.rename(id: saved.id, to: "New")
        store.replaceStyle(id: saved.id, with: look)
        let reloaded = StylePresetStore(fileURL: url)
        #expect(reloaded.presets.first?.name == "New")
        #expect(reloaded.presets.first?.style == look)
    }

    @Test func emptyNamesGetANumberedFallbackAndLongNamesAreTrimmed() {
        let store = StylePresetStore(fileURL: url)
        #expect(store.save(name: "   ", style: look).name == L10n.tr("Preset %lld", 1))
        #expect(store.save(name: String(repeating: "x", count: 100), style: look).name.count == StylePresetStore.maxNameLength)
    }

    @Test func corruptFileLoadsAsEmpty() throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: url)
        #expect(StylePresetStore(fileURL: url).presets.isEmpty)
    }

    @Test func editorModelStartsWithTheDefaultPreset() {
        let store = StylePresetStore(fileURL: url)
        let image = NSImage(size: CGSize(width: 40, height: 30))
        #expect(ScreenshotEditorModel(image: image, presets: store).style == .plain)
        store.setDefault(id: store.save(name: "Default", style: look).id)
        #expect(ScreenshotEditorModel(image: image, presets: store).style == look)
    }
}
