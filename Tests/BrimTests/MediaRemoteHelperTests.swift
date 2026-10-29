import Foundation
import Testing
@testable import Brim

struct MediaRemoteHelperTests {
    @Test func sentWithoutErrorIsAccepted() throws {
        #expect(try NowPlayingMediaRemote.accepted("sent 0\n"))
    }

    @Test func playerErrorIsNotAccepted() throws {
        #expect(try !NowPlayingMediaRemote.accepted("sent 3\n"))
        #expect(try !NowPlayingMediaRemote.accepted("sent -1"))
    }

    @Test func missingPlayerExplainsItself() {
        #expect(throws: NowPlayingFailure.self) { try NowPlayingMediaRemote.accepted("notfound\n") }
    }

    /// A command aimed at a player macOS isn't treating as now playing lands on the one it is
    /// (a film in Arc instead of YouTube Music), so the helper refuses rather than sending it.
    @Test func aPlayerThatIsNotNowPlayingIsRefused() {
        #expect(throws: NowPlayingMediaRemote.NotNowPlaying.self) { try NowPlayingMediaRemote.accepted("notnowplaying\n") }
    }

    @Test func unexpectedOutputIsRejected() {
        for output in ["invalid\n", "", "sent", "sent zero", "Can't load library"] {
            #expect(throws: NowPlayingFailure.self) { try NowPlayingMediaRemote.accepted(output) }
        }
    }

    @Test func onlyBundledHelperFilesAreUsed() {
        let root = URL(fileURLWithPath: "/Applications/Brim.app/Contents/Resources")
        let helper = NowPlayingMediaRemote.helper(in: root, exists: { _ in true })
        #expect(helper?.script.path == "/Applications/Brim.app/Contents/Resources/brim-mediaremote.pl")
        #expect(helper?.library.path == "/Applications/Brim.app/Contents/Resources/BrimMediaRemote.dylib")
        #expect(NowPlayingMediaRemote.helper(in: root, exists: { _ in false }) == nil)
        #expect(NowPlayingMediaRemote.helper(in: nil, exists: { _ in true }) == nil)
    }
}
