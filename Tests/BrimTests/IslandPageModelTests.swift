import Foundation
import Testing

@testable import Brim

/// The open island's page model (Home / Tray / Widgets), its sizes, and the Dynamic Glass melt.
@MainActor
struct IslandPageModelTests {
  @Test func pagesMapOntoThePresentationFlags() {
    #expect(IslandNavigation().page == .home)
    #expect(IslandNavigation.showing(.tray).page == .tray)
    #expect(IslandNavigation.showing(.widgets).page == .widgets)
    #expect(IslandNavigation.showing(.widgets).openedWidget == nil)
    #expect(IslandNavigation.showing(.clipboard).page == .clipboard)
  }

  @Test func clipboardIsItsOwnPageAndCalendarOpensAsAWidget() {
    let clipboard = IslandNavigation.opening(.clipboard)
    #expect(clipboard.page == .clipboard && clipboard.openedWidget == nil)
    #expect(clipboard == .showing(.clipboard))
    #expect(clipboard.library && clipboard.clipboard)
    let calendar = IslandNavigation.opening(.calendar)
    #expect(calendar.page == .widgets && calendar.openedWidget == .calendar)
    let weather = IslandNavigation.opening(.weather)
    #expect(weather.page == .widgets && weather.openedWidget == .weather)
  }

  /// ⌥⇧Space sets the old library flags directly; it must land on the Clipboard page.
  @Test func clipboardHotkeyFlagsReachTheClipboardPage() {
    let presentation = NotchPresentation()
    presentation.isShowingLibrary = true
    presentation.openedFromClipboard = true
    #expect(presentation.navigation.page == .clipboard)
  }

  @Test func navigatingResetsTheOtherPages() {
    let presentation = NotchPresentation()
    presentation.navigate(to: .opening(.clipboard))
    presentation.navigate(to: .showing(.tray))
    #expect(presentation.navigation.page == .tray)
    #expect(presentation.trayTab == .files)
    #expect(!presentation.openedFromClipboard)
    presentation.navigate(to: .opening(.timer))
    #expect(presentation.navigation.openedWidget == .timer)
    presentation.navigate(to: .showing(.home))
    #expect(presentation.navigation.page == .home && presentation.homeTapped)
  }

  @Test func swipeWalksHomeClipboardMusicWidgetsAndTheTrayOnlyWhenItHoldsFiles() {
    let empty = IslandPageOrder.visible(trayCount: 0, current: .home)
    #expect(empty == [.home, .clipboard, .music, .widgets])
    #expect(IslandPageOrder.page(from: .home, delta: 1, in: empty) == .clipboard)
    #expect(IslandPageOrder.page(from: .clipboard, delta: 1, in: empty) == .music)
    #expect(IslandPageOrder.page(from: .music, delta: 1, in: empty) == .widgets)
    #expect(IslandPageOrder.page(from: .widgets, delta: 1, in: empty) == nil)
    let full = IslandPageOrder.visible(trayCount: 2, current: .home)
    #expect(full == [.home, .clipboard, .tray, .music, .widgets])
    #expect(IslandPageOrder.page(from: .clipboard, delta: 1, in: full) == .tray)
    #expect(IslandPageOrder.page(from: .tray, delta: 1, in: full) == .music)
    // A drop opens the empty tray's page; its tab stays until the user leaves it.
    #expect(IslandPageOrder.visible(trayCount: 0, current: .tray) == [.home, .clipboard, .tray, .music, .widgets])
  }

  @Test func messagesTabShowsLastAndOnlyWhileTheInboxHoldsChats() {
    #expect(IslandPageOrder.visible(trayCount: 0, current: .home, messageCount: 0) == [.home, .clipboard, .music, .widgets])
    let withChats = IslandPageOrder.visible(trayCount: 0, current: .home, messageCount: 2)
    #expect(withChats == [.home, .clipboard, .music, .widgets, .messages])
    #expect(IslandPageOrder.page(from: .widgets, delta: 1, in: withChats) == .messages)
    // "Clear All" empties the inbox while its page is open; the tab stays until the user leaves.
    #expect(IslandPageOrder.visible(trayCount: 0, current: .messages, messageCount: 0).last == .messages)
  }

  @Test func navigatingToMessagesAndAwayClearsItsFlag() {
    let presentation = NotchPresentation()
    presentation.navigate(to: .showing(.messages))
    #expect(presentation.navigation.page == .messages && presentation.isShowingMessages)
    presentation.navigate(to: .showing(.clipboard))
    #expect(presentation.navigation.page == .clipboard && !presentation.isShowingMessages)
    #expect(IslandPage.fromStored(IslandPage.messages.storedName) == .messages)
  }

  @Test func everyToolStaysReachableFromTheWidgetsPage() {
    for activity in ActivityToolsView.primaryActivities {
      #expect(IslandWidgetTile(activity: activity) != nil, "\(activity) has no widget tile")
    }
    #expect(IslandWidgetTile(activity: .music) == .nowPlaying)
    #expect(IslandWidgetTile.allCases.filter { !$0.opensInIsland }.isEmpty)
  }

  @Test func traySizeGrowsToTwoRowsThenScrolls() {
    let one = IslandPageLayout.trayHeight(count: 3)
    let two = IslandPageLayout.trayHeight(count: 5)
    #expect(two > one)
    #expect(IslandPageLayout.trayHeight(count: 40) == two)
    // The one-row tray is ~190 pt tall on a 32 pt notch.
    #expect(abs(one + 32 - 190) <= 8)
  }

  @Test func widgetsGridShowsAtMostTwoRows() {
    let rows2 = IslandPageLayout.widgetsHeight(tiles: 8)
    #expect(IslandPageLayout.widgetsHeight(tiles: 18) == rows2)
    #expect(IslandPageLayout.widgetsHeight(tiles: 4) < rows2)
    #expect(abs(rows2 + 32 - 320) <= 10)
  }

  @Test func dynamicGlassMeltsFromBlackToGlass() {
    let melt = DynamicGlassMelt(style: .dynamicGlass, height: 300, solidHeight: 40, level: 0.5)
    #expect(melt.stops.first?.blackOpacity == 1)
    #expect((melt.stops.last?.blackOpacity ?? 1) < 0.5)
    let moreGlass = DynamicGlassMelt(style: .dynamicGlass, height: 300, solidHeight: 40, level: 1)
    #expect(moreGlass.stops[1].location < melt.stops[1].location)
    #expect((moreGlass.stops.last?.blackOpacity ?? 1) < (melt.stops.last?.blackOpacity ?? 0))
    let black = DynamicGlassMelt(style: .black, height: 300, solidHeight: 40, level: 1)
    #expect(black.stops.allSatisfy { $0.blackOpacity == 1 })
    let liquid = DynamicGlassMelt(style: .liquidGlass, height: 300, solidHeight: 0, level: 0.5)
    #expect(liquid.stops.allSatisfy { $0.blackOpacity == 0 })
  }

  @Test func themingSettingsPersistAndHonourTheOldGlassSwitch() throws {
    let defaults = try #require(UserDefaults(suiteName: "qs-theming-\(UUID().uuidString)"))
    let settings = AppSettings(defaults: defaults)
    #expect(settings.islandSurfaceStyle == .dynamicGlass)
    settings.islandGlassEnabled = false
    #expect(settings.islandSurfaceStyle == .black)
    settings.islandSurfaceStyle = .liquidGlass
    #expect(settings.islandGlassEnabled)
    settings.islandGlassLevel = 3
    #expect(settings.islandGlassLevel == 1)
    #expect(settings.islandGlassTinted)
    let theme = IslandTheme(settings: settings)
    theme.setTinted(false)
    #expect(!settings.islandGlassTinted && theme.surface == .liquidGlass)
  }

  @Test func transformMenuPreselectsItsOperationOnce() throws {
    let fixtures = try TransformFixtures()
    defer { fixtures.cleanup() }
    let image = try fixtures.image("a.jpg")
    TransformLaunchRequest.shared.operation = .resize
    #expect(TransformLaunchRequest.shared.makeModel(for: [image]).operation == .resize)
    #expect(TransformLaunchRequest.shared.operation == nil)
    #expect(TransformLaunchRequest.shared.makeModel(for: [image]).operation != .resize)
  }

  /// Leaving the island on the Clipboard and hovering back finds the Clipboard, not Home.
  @Test func plainHoverReopensOnTheLastPage() {
    let clipboard = NotchPresentation()
    clipboard.restorePage(.opening(.clipboard))
    #expect(clipboard.navigation.page == .clipboard)

    let timer = NotchPresentation()
    timer.restorePage(.opening(.timer))
    #expect(timer.navigation.page == .widgets && timer.navigation.openedWidget == .timer)
  }

  @Test func explicitOpensWinOverTheRememberedPage() {
    let hotkey = NotchPresentation()
    hotkey.navigate(to: .showing(.tray))
    hotkey.restorePage(.opening(.timer))
    #expect(hotkey.navigation.page == .tray)

    let notification = NotchPresentation()
    notification.expandedForNotification = true
    notification.restorePage(.opening(.clipboard))
    #expect(notification.navigation.page == .home)

    let home = NotchPresentation()
    home.restorePage(.showing(.home))
    #expect(!home.homeTapped)
  }

  /// Music is its own page (the music tab): its own flag, cleared by any other page.
  @Test func musicIsItsOwnPage() {
    let presentation = NotchPresentation()
    presentation.navigate(to: .showing(.music))
    #expect(presentation.navigation.page == .music && presentation.isShowingMusic)
    #expect(!presentation.homeTapped)
    presentation.navigate(to: .showing(.clipboard))
    #expect(!presentation.isShowingMusic)
    #expect(IslandPage.fromStored("music") == .music && IslandPage.music.storedName == "music")
    #expect(IslandPage.music.symbol == "music.note")
  }

  /// With no remembered page the island opens on Music while the closed island shows the song,
  /// else on Home; a remembered page (Home included) or an explicit Home wins.
  @Test func firstOpenOverASongLandsOnMusic() {
    let song = NotchPresentation()
    song.restorePage(nil, closedOnMusic: true)
    #expect(song.navigation.page == .music)

    let idle = NotchPresentation()
    idle.restorePage(nil, closedOnMusic: false)
    #expect(idle.navigation.page == .home)

    let leftOnHome = NotchPresentation()
    leftOnHome.restorePage(.showing(.home), closedOnMusic: true)
    #expect(leftOnHome.navigation.page == .home)

    let clickedHome = NotchPresentation()
    clickedHome.navigate(to: .showing(.home))
    clickedHome.restorePage(nil, closedOnMusic: true)
    #expect(clickedHome.navigation.page == .home)

    let remembered = NotchPresentation()
    remembered.restorePage(.showing(.music))
    #expect(remembered.navigation.page == .music)
  }

  /// The grid splits into pages of two full rows; the last page keeps whatever is left.
  @Test func widgetGridSplitsIntoTwoRowPages() {
    let pages = IslandWidgetGrid.pages(of: Array(0..<19))
    #expect(pages.map(\.count) == [8, 8, 3])
    #expect(pages.last == [16, 17, 18])
    #expect(IslandWidgetGrid.pages(of: [Int]()).isEmpty)
    #expect(IslandWidgetGrid.pages(of: Array(0..<8)).count == 1)
  }

  /// A trackpad gesture turns one page once it travels far enough, never more, and leaves
  /// horizontal swipes to the island's page navigation.
  @Test func widgetPagerTrackpadStepsOncePerGesture() {
    var pager = IslandWidgetPager()
    #expect(pager.trackpad(dy: -10, dx: 0, began: true, ended: false, momentum: false) == .hold)
    #expect(pager.trackpad(dy: -20, dx: 0, began: false, ended: false, momentum: false) == .step(1))
    #expect(pager.trackpad(dy: -80, dx: 0, began: false, ended: false, momentum: false) == .hold)
    #expect(pager.trackpad(dy: 0, dx: 0, began: false, ended: true, momentum: false) == .hold)
    #expect(pager.trackpad(dy: -40, dx: 0, began: false, ended: false, momentum: true) == .pass)

    #expect(pager.trackpad(dy: 30, dx: 2, began: true, ended: false, momentum: false) == .step(-1))

    #expect(pager.trackpad(dy: 1, dx: -20, began: true, ended: false, momentum: false) == .pass)
    #expect(pager.trackpad(dy: -40, dx: -5, began: false, ended: false, momentum: false) == .pass)
  }

  /// Each mouse-wheel notch turns one page; a fast spin waits out the cooldown instead of skipping pages.
  @Test func widgetPagerWheelStepsPerNotch() {
    var pager = IslandWidgetPager()
    #expect(pager.wheel(dy: -1, dx: 0, now: 10) == .step(1))
    #expect(pager.wheel(dy: -1, dx: 0, now: 10.1) == .hold)
    #expect(pager.wheel(dy: -1, dx: 0, now: 10.1 + IslandWidgetPager.wheelCooldown) == .step(1))
    #expect(pager.wheel(dy: 3, dx: 0, now: 20) == .step(-1))
    #expect(pager.wheel(dy: 0, dx: 2, now: 30) == .pass)
  }

  /// Smooth-scrolling mice (LinearMouse, Mos) send small precise deltas with no gesture phase:
  /// they add up to one page, and a pause starts the count again.
  @Test func widgetPagerSmoothWheelAddsUpToAPage() {
    var pager = IslandWidgetPager()
    #expect(pager.wheel(dy: -10, dx: 0, precise: true, now: 1) == .hold)
    #expect(pager.wheel(dy: -10, dx: 0, precise: true, now: 1.02) == .hold)
    #expect(pager.wheel(dy: -10, dx: 0, precise: true, now: 1.04) == .step(1))
    #expect(pager.wheel(dy: -30, dx: 0, precise: true, now: 1.1) == .hold)
    #expect(pager.wheel(dy: 10, dx: 0, precise: true, now: 3) == .hold)
    #expect(pager.wheel(dy: 20, dx: 0, precise: true, now: 3.02) == .step(-1))
  }
}
