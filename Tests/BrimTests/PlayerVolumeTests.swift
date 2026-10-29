import Testing
@testable import Brim

@MainActor
struct PlayerVolumeTests {
    @Test func sliderClampsAndReadsBackActualVolume() {
        var actual = SystemVolumeControl.State(level: 0.4, muted: false)
        let model = PlayerVolumeModel(read: { actual }, write: { actual.level = $0; return true })
        model.setLevel(2)
        #expect(model.level == 1)
        model.setLevel(-1)
        #expect(model.level == 0)
    }

    @Test func failedWriteRestoresHardwareState() {
        let actual = SystemVolumeControl.State(level: 0.4, muted: false)
        let model = PlayerVolumeModel(read: { actual }, write: { _ in false })
        model.setLevel(0.9)
        #expect(model.level == 0.4)
        #expect(model.errorMessage != nil)
    }

    @Test func unavailableOutputAndInvalidLevelsNeverWrite() {
        var writes = 0
        let model = PlayerVolumeModel(read: { nil }, write: { _ in writes += 1; return true })
        model.setLevel(0.4)
        #expect(!model.isAvailable)
        #expect(writes == 0)
        let supported = PlayerVolumeModel(read: { .init(level: 0.4, muted: false) },
                                         write: { _ in writes += 1; return true })
        supported.setLevel(.nan)
        supported.setLevel(.infinity)
        #expect(writes == 0)
    }

    @Test func draggingUpFromMuteUnmutesTheOutput() {
        var actual = SystemVolumeControl.State(level: 0.4, muted: true)
        let model = PlayerVolumeModel(read: { actual }, write: { actual.level = $0; return true },
                                      unmute: { actual.muted = false; return true })
        #expect(model.level == 0)
        model.setLevel(0.6)
        #expect(!actual.muted)
        #expect(model.level == 0.6)
    }
}
