import CoreGraphics
import Foundation
import Testing

@testable import Brim

@MainActor
struct HomeWidgetStoreTests {
  private func item(_ widget: HomeWidget, _ size: HomeWidgetSize) -> HomeWidgetItem { HomeWidgetItem(widget, size) }

  /// Every widget declares its sizes; its default is one of them.
  @Test func everyWidgetDeclaresItsSizes() {
    for widget in HomeWidget.allCases {
      #expect(!widget.sizes.isEmpty)
      #expect(widget.supports(widget.defaultSize), "\(widget) default unsupported")
    }
    #expect(HomeWidget.lyrics.sizes == [.medium])
    #expect(HomeWidget.awake.sizes == [.small])
    #expect(HomeWidget.media.defaultSize == .medium && HomeWidget.media.supports(.small))
    #expect(HomeWidget.batteries.sizes == [.small, .medium])
    #expect(HomeWidget.clock.defaultSize == .small)
    // An unsupported size asked for falls back to the default.
    #expect(HomeWidgetItem(.lyrics, .small).size == .medium)
  }

  /// Saved as before for default sizes ("media"), as "name:size" otherwise; old saves get defaults.
  @Test func storedFormatRoundTripsAndMigrates() {
    #expect(item(.media, .medium).stored == "media")
    #expect(item(.media, .small).stored == "media:small")
    #expect(HomeWidgetItem(stored: "media") == item(.media, .medium))
    #expect(HomeWidgetItem(stored: "clock") == item(.clock, .small))
    #expect(HomeWidgetItem(stored: "clock:medium") == item(.clock, .medium))
    #expect(HomeWidgetItem(stored: "clock:huge") == item(.clock, .small))
    #expect(HomeWidgetItem(stored: "nope") == nil)
    var saved: [String] = []
    let store = HomeWidgetStore(widgets: [.media, .clock], persist: { saved = $0.map(\.stored) })
    store.setSize(.clock, .medium)
    #expect(saved == ["media", "clock:medium"])
  }

  /// Pages hold four units; a medium that does not fit a page's last unit starts the next page.
  @Test func pagesFillFourUnitsInOrder() {
    let s = { (w: HomeWidget) in HomeWidgetItem(w, .small) }
    let m = { (w: HomeWidget) in HomeWidgetItem(w, .medium) }
    #expect(HomeWidgetGrid.pages([m(.media), s(.clock), s(.timer)]) == [[m(.media), s(.clock), s(.timer)]])
    #expect(HomeWidgetGrid.pages([s(.clock), m(.media), m(.notes)]) == [[s(.clock), m(.media)], [m(.notes)]])
    #expect(HomeWidgetGrid.pages([]).isEmpty)
    #expect(HomeWidgetGrid.fits([m(.media), m(.notes), m(.batteries), m(.weather)]))
    #expect(!HomeWidgetGrid.fits([s(.clock), m(.media), m(.notes), m(.batteries), s(.timer)]))  // S M | M M | S
    #expect(HomeWidgetGrid.units([m(.media), s(.clock)]) == 3)
  }

  @Test func addsUpToTwoPagesRemovesAndReorders() {
    var saved: [HomeWidgetItem] = []
    let store = HomeWidgetStore(items: [HomeWidgetItem(.captures, .small)], persist: { saved = $0 })
    for widget in [HomeWidget.timer, .clock, .agenda, .awake, .notes] { store.toggle(widget) }
    // S S S S | S M — then a medium no longer fits a page, and Media's small would.
    #expect(store.widgets == [.captures, .timer, .clock, .agenda, .awake, .notes])
    #expect(store.pages.count == 2)
    store.toggle(.media)
    #expect(store.size(of: .media) == .small)  // one unit left on page two: Media comes in small
    store.toggle(.media)
    store.toggle(.notes)
    store.toggle(.media)  // three units free on page two: Media fits at its default (medium)
    #expect(store.size(of: .media) == .medium)
    store.move(.agenda, before: .captures)
    #expect(store.widgets.prefix(2) == [.agenda, .captures])
    store.toggle(.agenda)
    #expect(!store.widgets.contains(.agenda))
    #expect(saved == store.items)
  }

  /// With one unit left, a widget whose default is medium is added small when it supports small.
  @Test func addingFallsBackToSmallWhenOnlyOneUnitIsLeft() {
    let store = HomeWidgetStore(
      items: [item(.media, .medium), item(.notes, .medium), item(.batteries, .medium), item(.clock, .small)],
      persist: { _ in })
    #expect(store.addableSize(.weather) == .small)
    store.toggle(.weather)
    #expect(store.size(of: .weather) == .small)
    #expect(!store.canAdd(.lyrics))  // medium only, and the pages are full
  }

  @Test func placingMovesOrInsertsAtAnIndex() {
    let store = HomeWidgetStore(widgets: [.media, .batteries], persist: { _ in })
    store.place(.batteries, at: 0)
    #expect(store.widgets == [.batteries, .media])
    store.place(.batteries, at: 9)  // past the end clamps to the end
    #expect(store.widgets == [.media, .batteries])
    store.place(.clock, at: 1)  // from the dock: lands where dropped, at its default size
    #expect(store.items == [item(.media, .medium), item(.clock, .small), item(.batteries, .medium)])
    // M M | S M still fits; another medium in front would need a third page.
    store.place(.weather, at: 0)
    #expect(store.pages.count == 2)
    store.place(.lyrics, at: 0)
    #expect(!store.widgets.contains(.lyrics))
  }

  /// A move that would push a widget onto a third page is refused.
  @Test func reorderThatOverflowsIsRefused() {
    let store = HomeWidgetStore(
      items: [item(.media, .medium), item(.notes, .medium), item(.clock, .small), item(.timer, .small),
              item(.batteries, .medium)],
      persist: { _ in })
    let before = store.items
    store.place(.batteries, at: 2)  // M M | M S S: fits
    #expect(store.widgets == [.media, .notes, .batteries, .clock, .timer])
    store.restore(before)
    store.place(.clock, at: 0)  // S M | M S | M: three pages
    #expect(store.items == before)
  }

  @Test func setSizeRespectsSupportAndRoom() {
    let store = HomeWidgetStore(widgets: [.media, .clock, .timer], persist: { _ in })
    store.setSize(.media, .small)
    #expect(store.size(of: .media) == .small)
    store.setSize(.clock, .medium)
    #expect(store.pages.map { HomeWidgetGrid.units($0) } == [4])
    store.setSize(.awake, .medium)  // not on the shelf, and small only
    #expect(store.size(of: .awake) == nil)
    let full = HomeWidgetStore(
      items: [item(.media, .medium), item(.notes, .medium), item(.batteries, .medium), item(.clock, .small),
              item(.timer, .small)],
      persist: { _ in })
    #expect(!full.canResize(.clock, to: .medium))
    full.setSize(.clock, .medium)
    #expect(full.size(of: .clock) == .small)
  }

  /// Old layouts held six wide widgets; they keep what fits, shrinking to small where that helps.
  @Test func oversizedSavedLayoutsAreFitted() {
    let store = HomeWidgetStore(
      widgets: [.media, .weather, .batteries, .notes, .stats, .clock], persist: { _ in })
    #expect(store.pages.count <= HomeWidgetGrid.maxPages)
    #expect(store.widgets.prefix(4) == [.media, .weather, .batteries, .notes])
    #expect(HomeWidgetGrid.fits(store.items))
  }

  /// Where a dragged widget lands: before the first other widget whose middle is right of the pointer.
  /// A dragged widget must stay on the page under the pointer, or its view (and the drag) ends.
  @Test func placeKeepingPageNeverPushesTheWidgetToAnotherPage() {
    let store = HomeWidgetStore(items: [HomeWidgetItem(.media, .medium), HomeWidgetItem(.clock, .small),
                                        HomeWidgetItem(.weather, .medium), HomeWidgetItem(.timer, .small)],
                                persist: { _ in })
    let before = store.items
    #expect(HomeWidgetGrid.pages(before).count == 2)
    store.place(.clock, at: 2, keepingPage: 0)
    #expect(HomeWidgetGrid.pages(store.items)[0].contains { $0.widget == .clock })
    store.place(.clock, at: 0, keepingPage: 0)
    #expect(store.items.first?.widget == .clock)
  }

  @Test func insertionIndexFollowsThePointer() {
    let frames: [HomeWidget: CGRect] = [
      .media: CGRect(x: 0, y: 0, width: 292, height: 140),
      .batteries: CGRect(x: 304, y: 0, width: 140, height: 140),
      .timer: CGRect(x: 456, y: 0, width: 140, height: 140),
    ]
    let order: [HomeWidget] = [.media, .batteries, .timer]
    #expect(HomeWidgetDrag.insertionIndex(x: 10, order: order, frames: frames, dragging: nil) == 0)
    #expect(HomeWidgetDrag.insertionIndex(x: 400, order: order, frames: frames, dragging: nil) == 2)
    #expect(HomeWidgetDrag.insertionIndex(x: 700, order: order, frames: frames, dragging: nil) == 3)
    #expect(HomeWidgetDrag.insertionIndex(x: 400, order: order, frames: frames, dragging: .media) == 1)
    #expect(HomeWidgetDrag.insertionIndex(x: 20, order: order, frames: frames, dragging: .timer) == 0)
  }

  /// Media is the default Home widget and is always on the shelf, even with nothing playing.
  @Test func mediaIsAShelfWidgetAndADefault() {
    let store = HomeWidgetStore(widgets: [.media, .clock], persist: { _ in })
    #expect(store.shelfWidgets == [.media, .clock])
    #expect(store.showsIdlePlayer)
    let removed = HomeWidgetStore(widgets: [.clock], persist: { _ in })
    #expect(!removed.showsIdlePlayer)
    let defaults = UserDefaults(suiteName: "home-widgets-default-\(UUID().uuidString)")!
    #expect(AppSettings(defaults: defaults).homeWidgets.contains("media"))
  }

  /// Media could not be removed from the shelf before, so a saved list without it was never a choice.
  @Test func migrationGivesExistingUsersMediaOnce() {
    let defaults = UserDefaults(suiteName: "home-widgets-migrate-\(UUID().uuidString)")!
    defaults.set(["clock", "timer"], forKey: "homeWidgets")
    let settings = AppSettings(defaults: defaults)
    #expect(settings.homeWidgets == ["media", "clock", "timer"])
    // Removing it afterwards is explicit and stays removed.
    settings.homeWidgets = ["clock", "timer"]
    #expect(AppSettings(defaults: defaults).homeWidgets == ["clock", "timer"])
  }

  @Test func migrationFillsAnEmptyList() {
    let defaults = UserDefaults(suiteName: "home-widgets-empty-\(UUID().uuidString)")!
    defaults.set([String](), forKey: "homeWidgets")
    #expect(AppSettings(defaults: defaults).homeWidgets == ["media"])
  }

  /// The old six-widget list plus Media; the store then keeps what fits two pages.
  @Test func migrationKeepsEveryOldWidgetForTheStoreToFit() {
    let defaults = UserDefaults(suiteName: "home-widgets-six-\(UUID().uuidString)")!
    defaults.set(["clock", "timer", "stats", "notes", "weather", "agenda"], forKey: "homeWidgets")
    let settings = AppSettings(defaults: defaults)
    let list = settings.homeWidgets
    #expect(list.count == 7 && list.first == "media")
    // Eight small widgets fill both pages, and are all kept.
    settings.homeWidgets = (0..<9).map { "w\($0)" }
    #expect(settings.homeWidgets.count == HomeWidgetGrid.maxWidgets)
  }
}

/// The island's width is built from the grid, exactly, and can never pass NotchGeometry's cap —
/// the cap was what cut the outer cards before (a 790 pt row in a 740 pt island).
@MainActor
struct HomeWidgetGridTests {
  @Test func unitMaths() {
    #expect(HomeWidgetGrid.width(units: 1) == 140)
    #expect(HomeWidgetGrid.width(units: 2) == 292)
    #expect(HomeWidgetSize.medium.width == 2 * HomeWidgetSize.small.width + HomeWidgetGrid.gap)
    #expect(HomeWidgetGrid.width(units: 4) == 596)
  }

  @Test func shelfWidthIsExact() {
    let store = HomeWidgetStore(widgets: [.media, .clock, .timer], persist: { _ in })
    #expect(store.gridWidth == 596)
    #expect(store.shelfWidth == 596 + HomeWidgetStore.horizontalPadding)
    store.isEditing = true
    #expect(store.shelfWidth == 596 + HomeWidgetStore.horizontalPadding + 2 * HomeWidgetStore.editMargin)
    // A lone small widget still gets two units of island.
    let lone = HomeWidgetStore(widgets: [.clock], persist: { _ in })
    #expect(lone.gridWidth == HomeWidgetGrid.width(units: 2))
    // Two pages keep the widest page's width on both.
    let paged = HomeWidgetStore(widgets: [.clock, .media, .notes], persist: { _ in })
    #expect(paged.pages.count == 2 && paged.gridWidth == HomeWidgetGrid.width(units: 3))
  }

  /// Every combination of sizes, editing or not, on a notched Mac and on the pill: the open island is
  /// exactly as wide as the grid asks for (never clamped), and every page fits inside the grid.
  @Test func islandIsNeverNarrowerThanTheGrid() {
    let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let notch = NotchGeometry(screenFrame: screen, notchWidth: 184, notchHeight: 32)
    let pill = NotchGeometry.dynamicIsland(screenFrame: screen)
    let widgets = HomeWidget.allCases
    var checked = 0
    for mask in 0..<(1 << widgets.count) {
      let items = widgets.enumerated().map { HomeWidgetItem($1, mask & (1 << $0) == 0 ? .small : .medium) }
      for rotation in [0, 3, 7] {
        let ordered = Array(items[rotation...] + items[..<rotation])
        let store = HomeWidgetStore(items: ordered, persist: { _ in })
        for editing in [false, true] {
          store.isEditing = editing
          for page in store.pages { #expect(HomeWidgetGrid.width(units: HomeWidgetGrid.units(page)) <= store.gridWidth) }
          for (geometry, shoulder) in [(notch, IslandPageLayout.openShoulder), (pill, CGFloat(0))] {
            var open = geometry
            open.preferredWidth = store.shelfWidth + 2 * shoulder
            open.utilityContentHeight = store.shelfHeight
            #expect(open.naturalExpandedSize.width == open.preferredWidth!)
          }
          checked += 1
        }
      }
    }
    #expect(checked > 10_000)
  }
}
