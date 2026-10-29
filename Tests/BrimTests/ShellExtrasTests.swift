import AppKit
import CoreGraphics
import Foundation
import Testing

@testable import Brim

@MainActor
private func freshSettings() -> AppSettings {
  AppSettings(defaults: UserDefaults(suiteName: "shell-extras-\(UUID().uuidString)")!)
}

@MainActor
struct ShellExtrasSettingsTests {
  @Test func defaultsKeepCurrentBehavior() {
    let s = freshSettings()
    #expect(s.shellClickAction == .open && s.shellShowNavigation && s.shellRevealModifier == .none)
    #expect(s.shellOpenSize == .regular && s.shellPinnedFavorites.isEmpty && !s.shellHidePhysicalNotch)
    #expect(s.shellDisabledDisplays.isEmpty)
    #expect(s.islandGlassClarity == 0.5 && s.islandLightGlassInLightMode && s.islandLowBatteryMode)
    #expect(!s.islandProgressiveBlur && s.islandHighlightHex.isEmpty && s.islandWindowTintHex.isEmpty)
    #expect(ShellTuning.current(s) == ShellTuning())
  }

  @Test func valuesRoundTripAndFavoritesCapAtFour() {
    let s = freshSettings()
    s.shellClickAction = .playPause
    s.shellRevealModifier = .option
    s.shellOpenSize = .enlarged
    s.shellPinnedFavorites = ["weather", "notes", "timer", "stats", "calendar"]
    #expect(s.shellClickAction == .playPause && s.shellRevealModifier == .option)
    #expect(s.shellPinnedFavorites.count == 4)
    let tuning = ShellTuning.current(s)
    #expect(tuning.openScale > 1 && tuning.favorites.map(\.rawValue) == ["weather", "notes", "timer", "stats"])
    s.islandGlassClarity = 4
    #expect(s.islandGlassClarity == 1)
  }
}

struct ShellExtrasPolicyTests {
  @Test func notchClickResolves() {
    #expect(NotchClickResolver.resolve(action: .open, page: "tray") == .open)
    #expect(NotchClickResolver.resolve(action: .openPage, page: "tray") == .openPage(.tray))
    #expect(NotchClickResolver.resolve(action: .openPage, page: "bogus") == .openPage(.home))
    #expect(NotchClickResolver.resolve(action: .playPause, page: "home") == .togglePlayback)
    #expect(NotchClickResolver.resolve(action: .nothing, page: "home") == .ignore)
  }

  @Test func revealNeedsModifierAndZone() {
    let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let trigger = CGRect(x: 650, y: 950, width: 212, height: 32)
    let zone = ShellRevealPolicy.zone(trigger: trigger, screen: screen)
    let near = CGPoint(x: 700, y: 975)
    #expect(ShellRevealPolicy.isRevealing(modifier: .option, held: [.option], pointer: near, zone: zone))
    #expect(!ShellRevealPolicy.isRevealing(modifier: .option, held: [.shift], pointer: near, zone: zone))
    #expect(!ShellRevealPolicy.isRevealing(modifier: .none, held: [.option], pointer: near, zone: zone))
    #expect(!ShellRevealPolicy.isRevealing(modifier: .option, held: [.option], pointer: CGPoint(x: 700, y: 600), zone: zone))
    #expect(!ShellRevealPolicy.isRevealing(modifier: .option, held: [.option], pointer: CGPoint(x: 100, y: 975), zone: zone))
  }

  @Test func revealOpensAHoverOffIslandOnlyWhileHeld() {
    var hover = ShelfHoverState()
    var timing = ShellTiming(opensOnHover: false)
    let first = hover.update(isInside: true, isDragging: false, now: 0, timing: timing)
    let later = hover.update(isInside: true, isDragging: false, now: 1, timing: timing)
    timing.opensOnHover = true  // what the controller does while the modifier is held
    let held = hover.update(isInside: true, isDragging: false, now: 1.3, timing: timing)
    #expect(!first && !later && held)
  }

  /// Every tile opens inside the island now (Screenshot became a page with capture modes), so the
  /// filter only drops duplicates and unknown names.
  @Test func favoritesFilterDuplicatesAndUnknown() {
    let tiles = IslandFavorites.tiles(from: ["weather", "weather", "nope", "screenshot", "notes"])
    #expect(tiles == [.weather, .screenshot, .notes])
    let full = ["weather", "notes", "timer", "stats"]
    #expect(IslandFavorites.toggled(.calendar, in: full) == full)
    #expect(IslandFavorites.toggled(.notes, in: full) == ["weather", "timer", "stats"])
    #expect(IslandFavorites.toggled(.calendar, in: ["weather"]) == ["weather", "calendar"])
  }

  @Test func menuBarBandOnlyOnNotchedDisplays() {
    let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    #expect(MenuBarBandLayout.frame(screenFrame: screen, safeAreaTop: 0) == nil)
    #expect(MenuBarBandLayout.frame(screenFrame: screen, safeAreaTop: 32) == CGRect(x: 0, y: 950, width: 1512, height: 32))
  }

  @Test func clarityKeepsTheDefaultAndMovesBothWays() {
    let normal = GlassClarity(0.5)
    #expect(abs(normal.veilOpacity(tinted: true) - 0.32) < 1e-9)
    #expect(abs(normal.veilOpacity(tinted: false) - 0.08) < 1e-9)
    #expect(abs(normal.blurRadius(base: 26) - 26) < 1e-6)
    #expect(GlassClarity(1).veilOpacity(tinted: true) == 0)
    #expect(GlassClarity(0).veilOpacity(tinted: true) > 0.6)
    #expect(GlassClarity(1).blurRadius(base: 26) < GlassClarity(0).blurRadius(base: 26))
  }

  @Test func lowBatteryTriggers() {
    #expect(LowBatteryPolicy.isActive(enabled: true, percent: 19, charging: false, lowPowerMode: false))
    #expect(!LowBatteryPolicy.isActive(enabled: true, percent: 20, charging: false, lowPowerMode: false))
    #expect(!LowBatteryPolicy.isActive(enabled: true, percent: 5, charging: true, lowPowerMode: false))
    #expect(LowBatteryPolicy.isActive(enabled: true, percent: 90, charging: true, lowPowerMode: true))
    #expect(!LowBatteryPolicy.isActive(enabled: false, percent: 1, charging: false, lowPowerMode: true))
    #expect(!LowBatteryPolicy.isActive(enabled: true, percent: nil, charging: false, lowPowerMode: false))
  }

  @Test func hexColorsParse() {
    #expect(IslandHex.rgb("#FF8000")?.g ?? 0 > 0.49)
    #expect(IslandHex.rgb("00ff00")?.g == 1)
    #expect(IslandHex.rgb("") == nil && IslandHex.rgb("#12") == nil && IslandHex.rgb("#GGGGGG") == nil)
  }

  @Test func disabledDisplayHidesTheIsland() {
    var context = ShellVisibilityContext()
    #expect(ShellVisibilityPolicy.decide(context) == .visible)
    context.displayDisabled = true
    #expect(ShellVisibilityPolicy.decide(context) == .hidden)
  }
}

@MainActor
struct ShellExtrasGeometryTests {
  private let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)

  private func notch(_ tuning: ShellTuning = ShellTuning()) -> NotchGeometry {
    NotchGeometry.make(screenFrame: screen, hardwareNotch: (200, 32), style: .island, tuning: tuning)
  }

  @Test func enlargedScalesTheOpenIslandAndWindow() {
    let regular = notch()
    let big = notch(ShellTuning(openScale: ShellOpenSize.enlarged.scale))
    let ratio = big.expandedSize.width / regular.expandedSize.width
    #expect(abs(ratio - ShellOpenSize.enlarged.scale) < 0.001)
    #expect(big.expandedSize.height > regular.expandedSize.height)
    #expect(big.hostingFrame.width >= big.expandedSize.width)
    #expect(big.hostingFrame.height >= big.expandedSize.height + IslandNavigationLayout.reserved)
    #expect(big.collapsedSize == regular.collapsedSize)
  }

  @Test func enlargedNeverExceedsTheDisplay() {
    let narrow = NotchGeometry.make(screenFrame: CGRect(x: 0, y: 0, width: 640, height: 400), hardwareNotch: nil,
                                    style: .island, tuning: ShellTuning(openScale: 2))
    #expect(narrow.expandedSize.width <= 640 - 24 + 0.001)
  }

  @Test func hiddenNavigationDropsTheCapsuleHitArea() {
    let withNav = notch()
    let without = notch(ShellTuning(showsNavigation: false))
    let below = CGPoint(x: withNav.screenFrame.midX, y: withNav.navigationFrame.midY)
    #expect(withNav.containsPointer(below, expanded: true))
    #expect(!without.containsPointer(below, expanded: true))
  }
}

@MainActor
struct TwoGlancesTests {
  private func model() -> IslandGlanceModel {
    IslandGlanceModel(settings: AppSettings(defaults: UserDefaults(suiteName: "glances-\(UUID().uuidString)")!),
                      battery: (64, false))
  }

  @Test func eachSideHoldsTwoGlancesAndReservesBothWidths() {
    let model = model()
    model.set(.clock, for: .left)
    #expect(model.reservedWidth(.left) == IslandGlanceModel.glanceWidth)
    model.set(.battery, for: .left, second: true)
    #expect(model.visible(for: .left) == [.clock, .battery])
    #expect(model.reservedWidth(.left) == 2 * IslandGlanceModel.glanceWidth + IslandGlanceModel.glanceSpacing)
    #expect(model.reservedWidth(.right) == 0)
  }

  @Test func duplicatesShowOnceAndSecondsPersist() {
    let defaults = UserDefaults(suiteName: "glances-\(UUID().uuidString)")!
    let model = IslandGlanceModel(settings: AppSettings(defaults: defaults), battery: (64, false))
    model.set(.clock, for: .right)
    model.set(.clock, for: .right, second: true)
    #expect(model.visible(for: .right) == [.clock])
    #expect(AppSettings(defaults: defaults).glanceRightSecond == "clock")
    let reloaded = IslandGlanceModel(settings: AppSettings(defaults: defaults))
    #expect(reloaded.rightSecond == .clock)
  }

  @Test func eventGlanceNeedsAMeeting() {
    let model = model()
    model.set(.event, for: .left)
    #expect(model.hasContent(.left) == (CalendarActivityModel.shared.meeting != nil))
    #expect(IslandGlanceModel.width(of: .event) > IslandGlanceModel.glanceWidth)
  }

  @Test func eventTextShortensTitleAndShowsNow() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let utc = TimeZone(identifier: "UTC")!
    let later = GlanceFormat.event(title: "Quarterly planning review", startsAt: now.addingTimeInterval(1800),
                                   now: now, locale: Locale(identifier: "en_US"), timeZone: utc)
    #expect(later.hasPrefix("Quarterly …") || later.hasPrefix("Quarterly "))
    #expect(GlanceFormat.event(title: "Standup", startsAt: now.addingTimeInterval(-60), now: now) == "Standup Now")
    #expect(GlanceFormat.event(title: "", startsAt: now.addingTimeInterval(-60), now: now) == "Now")
  }
}

@MainActor
struct IslandThemeExtrasTests {
  @Test func lowBatteryForcesBlackAndDropsBlur() {
    let theme = IslandTheme(surface: .liquidGlass, progressiveBlur: true, lowBattery: true)
    #expect(theme.effectiveSurface == .black && !theme.showsProgressiveBlur && !theme.usesLightGlass)
    let normal = IslandTheme(surface: .liquidGlass, progressiveBlur: true)
    #expect(normal.effectiveSurface == .liquidGlass && normal.showsProgressiveBlur)
  }

  @Test func lightGlassNeedsLightModeGlassAndTheOption() {
    #expect(IslandTheme(surface: .dynamicGlass, light: true).usesLightGlass)
    #expect(!IslandTheme(surface: .dynamicGlass, light: true, lightGlass: false).usesLightGlass)
    #expect(!IslandTheme(surface: .black, light: true).usesLightGlass)
    #expect(!IslandTheme(surface: .dynamicGlass, light: false).usesLightGlass)
  }

  @Test func lightnessThinsTheBlackBelowTheCamera() {
    let dark = DynamicGlassMelt(style: .dynamicGlass, height: 300, solidHeight: 38, level: 0.5)
    let light = DynamicGlassMelt(style: .dynamicGlass, height: 300, solidHeight: 38, level: 0.5, lightness: 1)
    #expect(light.stops.first?.blackOpacity == 1)
    #expect((light.stops.last?.blackOpacity ?? 1) < (dark.stops.last?.blackOpacity ?? 0))
  }
}
