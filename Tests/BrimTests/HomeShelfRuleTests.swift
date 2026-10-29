import Testing

@testable import Brim

/// Home is always the widget shelf (its Media widget is the small player). The full
/// player moved to the Music tab. A leading live activity's card still takes Home until Home is tapped.
struct HomeShelfRuleTests {
  @Test func tappingHomeShowsTheWidgetsEvenWhileAnAgentLeads() {
    #expect(NotchShelfView.showsShelf(homeTapped: true, editing: false, primary: .agent))
    #expect(!NotchShelfView.showsShelf(homeTapped: false, editing: false, primary: .agent))
  }

  /// With nothing playing the shelf's Media widget is the idle "Not playing" card, so Home never
  /// shows an empty "Add widgets" prompt when Media is on.
  @Test @MainActor func nothingPlayingStillShowsAMediaCard() {
    let store = HomeWidgetStore(widgets: [.media], persist: { _ in })
    #expect(NotchShelfView.showsShelf(homeTapped: false, editing: false, primary: nil))
    #expect(store.shelfWidgets == [.media])
    #expect(store.showsIdlePlayer)
  }

  @Test func aLeadingCallOrRecordingKeepsItsCard() {
    #expect(!NotchShelfView.showsShelf(homeTapped: false, editing: false, primary: .call))
    #expect(!NotchShelfView.showsShelf(homeTapped: false, editing: false, primary: .recording))
    #expect(NotchShelfView.showsShelf(homeTapped: false, editing: true, primary: .call))
  }

  /// Music leading no longer turns Home into the player: Home stays the widgets.
  @Test func musicLeavesHomeAsTheWidgets() {
    #expect(NotchShelfView.showsShelf(homeTapped: false, editing: false, primary: .music))
    #expect(NotchShelfView.showsShelf(homeTapped: true, editing: false, primary: .music))
  }

  @Test func editingAlwaysShowsTheShelf() {
    #expect(NotchShelfView.showsShelf(homeTapped: false, editing: true, primary: .agent))
  }
}
