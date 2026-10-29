import Testing

@testable import Brim

struct MediaButtonSlotsTests {
  private typealias Caps = MediaButtonSlots.Capabilities

  @Test func unsupportedButtonsAreHidden() {
    let appleMusic = Caps(hasFavorite: true, hasShuffle: false, lyricsEnabled: false)
    #expect(MediaButtonSlots.resolve([.favorite, .shuffle], capabilities: appleMusic) == [.favorite])
    #expect(MediaButtonSlots.resolve([.lyrics, .repeat, .none], capabilities: appleMusic).isEmpty)
    #expect(MediaButtonSlots.resolve([.output, .lyrics], capabilities: Caps(hasFavorite: false, hasShuffle: false, lyricsEnabled: true)) == [.output, .lyrics])
  }

  @Test func favoriteFallsBackToShuffleOnSpotify() {
    let spotify = Caps(hasFavorite: false, hasShuffle: true, lyricsEnabled: false)
    #expect(MediaButtonSlots.resolve([.favorite], capabilities: spotify) == [.shuffle])
    #expect(MediaButtonSlots.resolve([.favorite, .shuffle], capabilities: spotify) == [.shuffle])
  }

  @Test func capsAtTwoAndDeduplicates() {
    let all = Caps(hasFavorite: true, hasShuffle: true, lyricsEnabled: true)
    #expect(MediaButtonSlots.resolve([.output, .output, .lyrics, .shuffle], capabilities: all) == [.output, .lyrics])
  }

  @Test func centersKeepClassicSpotsForOneButton() {
    #expect(MediaButtonSlots.centers(count: 1, left: true) == [93.5])
    #expect(MediaButtonSlots.centers(count: 1, left: false) == [510])
    #expect(MediaButtonSlots.centers(count: 2, left: false).count == 2)
    #expect(MediaButtonSlots.centers(count: 0, left: true).isEmpty)
  }
}
