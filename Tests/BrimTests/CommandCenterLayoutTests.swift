import Foundation
import Testing

@testable import Brim

@Suite struct CommandCenterLayoutTests {
  @Test func heroAndSmallTilesPackIntoOnePage() {
    let layout = [TilePlacement(.nowPlaying, .hero), TilePlacement(.clipboard), TilePlacement(.captureArea),
                  TilePlacement(.ocr), TilePlacement(.transform)]
    let pages = CommandCenterLayout.paginate(layout)
    #expect(pages.count == 1)
    let hero = pages[0][0]
    #expect(hero.column == 0 && hero.row == 0)
    // Two small tiles fill the hero's right-hand 2x2 block row 0.
    #expect(pages[0][1].column == 2 && pages[0][1].row == 0)
    #expect(pages[0][2].column == 3 && pages[0][2].row == 0)
  }

  @Test func overflowOpensANewPage() {
    let all = TileKind.allCases.map { TilePlacement($0, .small) }
    let pages = CommandCenterLayout.paginate(all)
    #expect(pages.count >= 2)
    #expect(pages.flatMap { $0 }.count == all.count, "every tile lands somewhere")
    for page in pages {
      let cells = page.reduce(0) { $0 + $1.placement.size.columns * $1.placement.size.rows }
      #expect(cells <= CommandCenterLayout.columns * CommandCenterLayout.rows)
    }
  }

  @Test func noTilesOverlapOnAnyPage() {
    let pages = CommandCenterLayout.paginate(CommandCenterLayout.defaultPlacements)
    for page in pages {
      var taken = Set<[Int]>()
      for tile in page {
        for r in tile.row..<(tile.row + tile.placement.size.rows) {
          for c in tile.column..<(tile.column + tile.placement.size.columns) {
            #expect(r < CommandCenterLayout.rows && c < CommandCenterLayout.columns)
            #expect(taken.insert([r, c]).inserted, "cell \(r),\(c) used twice")
          }
        }
      }
    }
  }

  @Test func laterSmallTileBackfillsEarlierGap() {
    // Page 0 ends with a one-cell hole; a wide tile can't use it and opens page 1, a later small tile can.
    let layout = [TilePlacement(.nowPlaying, .hero), TilePlacement(.upcoming, .wide), TilePlacement(.network, .wide),
                  TilePlacement(.cpu, .wide), TilePlacement(.memory, .small), TilePlacement(.disk, .wide),
                  TilePlacement(.clipboard)]
    let placed = CommandCenterLayout.paginate(layout).flatMap { $0 }
    #expect(placed.first { $0.placement.kind == .disk }?.page == 1)
    #expect(placed.first { $0.placement.kind == .clipboard }?.page == 0)
  }

  @Test func emptyLayoutStillHasOnePageForDots() {
    #expect(CommandCenterLayout.pageCount([]) == 1)
  }

  @Test func startPageHonorsModeAndClampsLastUsed() {
    #expect(CommandCenterLayout.startPage(.first, lastUsed: 2, pageCount: 3) == 0)
    #expect(CommandCenterLayout.startPage(.lastUsed, lastUsed: 2, pageCount: 3) == 2)
    #expect(CommandCenterLayout.startPage(.lastUsed, lastUsed: 5, pageCount: 2) == 1)
  }

  // MARK: Editing

  @Test func addRemoveMoveResizeReturnNewArrays() {
    let base = [TilePlacement(.clipboard), TilePlacement(.ocr), TilePlacement(.settings)]
    #expect(CommandCenterLayout.adding(.clipboard, to: base) == base)
    #expect(CommandCenterLayout.adding(.cpu, to: base).last?.kind == .cpu)
    #expect(CommandCenterLayout.removing(.ocr, from: base).map(\.kind) == [.clipboard, .settings])
    #expect(CommandCenterLayout.moving(.settings, onto: .clipboard, in: base).map(\.kind) == [.settings, .clipboard, .ocr])
    #expect(CommandCenterLayout.shifting(.clipboard, by: 1, in: base).map(\.kind) == [.ocr, .clipboard, .settings])
    #expect(CommandCenterLayout.shifting(.clipboard, by: -1, in: base) == base)
    #expect(CommandCenterLayout.cyclingSize(.ocr, in: base)[1].size == .wide)
    #expect(base[1].size == .small, "input is never mutated")
  }

  @Test func sizeCycleStaysWithinAllowedSizes() {
    var layout = [TilePlacement(.nowPlaying)]
    for _ in 0..<5 {
      layout = CommandCenterLayout.cyclingSize(.nowPlaying, in: layout)
      #expect(TileKind.nowPlaying.allowedSizes.contains(layout[0].size))
    }
  }

  @Test func availableListsOnlyUnusedTiles() {
    let free = CommandCenterLayout.available(excluding: [TilePlacement(.clipboard)])
    #expect(!free.contains(.clipboard))
    #expect(free.count == TileKind.allCases.count - 1)
  }

  // MARK: Persistence

  @Test func serializeParseRoundTrips() {
    for preset in CommandCenterLayout.presets {
      #expect(CommandCenterLayout.parse(CommandCenterLayout.serialize(preset.placements)) == preset.placements)
    }
  }

  @Test func parseDropsUnknownDuplicatesAndBadSizes() {
    let parsed = CommandCenterLayout.parse("media.nowPlaying@small,bogus.kind@hero,action.ocr@hero,action.ocr@wide,action.settings")
    #expect(parsed.map(\.kind) == [.nowPlaying, .ocr, .settings])
    #expect(parsed[0].size == .hero, "small isn't allowed for Now Playing; falls back to its default")
    #expect(parsed[1].size == .small, "hero isn't allowed for OCR; falls back to default")
  }

  @Test func garbageAndNilYieldDefaultButExplicitEmptyIsKept() {
    #expect(CommandCenterLayout.parse(nil) == CommandCenterLayout.defaultPlacements)
    #expect(CommandCenterLayout.parse("???") == CommandCenterLayout.defaultPlacements)
    #expect(CommandCenterLayout.parse(CommandCenterLayout.storageString([])).isEmpty)
  }

  @MainActor @Test func storePersistsEditsAcrossInstances() {
    let suite = "cc.store.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AppSettings(defaults: defaults)
    let store = CommandCenterStore(settings: settings)
    store.remove(.network)
    store.add(.colorPicker)
    store.cycleSize(.cpu)
    store.move(.settings, onto: .clipboard)
    let reopened = CommandCenterStore(settings: AppSettings(defaults: defaults))
    #expect(reopened.placements == store.placements)
    #expect(!reopened.placements.contains { $0.kind == .network })
    #expect(reopened.placements.first?.kind == .nowPlaying || reopened.placements.contains { $0.kind == .colorPicker })
    #expect(reopened.placements.first { $0.kind == .cpu }?.size == .wide)
  }

  @MainActor @Test func presetReplacesLayout() {
    let defaults = UserDefaults(suiteName: "cc.preset.\(UUID().uuidString)")!
    let store = CommandCenterStore(settings: AppSettings(defaults: defaults))
    let minimal = CommandCenterLayout.presets.first { $0.id == "minimal" }!
    store.apply(minimal)
    #expect(store.placements == minimal.placements)
    #expect(store.pageCount == 1)
  }
}

@Suite struct MenuBarStatusPolicyTests {
  typealias Input = MenuBarStatusPolicy.Input

  @Test func idleByDefault() {
    #expect(MenuBarStatusPolicy.output(Input()) == .init(icon: .idle, title: ""))
  }

  @Test func priorityRecordingThenAgentInputThenTimerThenAgentThenMusic() {
    var input = Input(isRecording: true, timerRemaining: 90, agentRunning: true, agentNeedsInput: true, musicPlaying: true)
    #expect(MenuBarStatusPolicy.output(input).icon == .recording)
    input.isRecording = false
    #expect(MenuBarStatusPolicy.output(input).icon == .agentNeedsInput)
    input.agentNeedsInput = false
    #expect(MenuBarStatusPolicy.output(input).icon == .timer)
    input.timerRemaining = nil
    #expect(MenuBarStatusPolicy.output(input).icon == .agent)
    input.agentRunning = false
    #expect(MenuBarStatusPolicy.output(input).icon == .music)
    input.musicPlaying = false
    #expect(MenuBarStatusPolicy.output(input).icon == .idle)
  }

  @Test func liveStatusOffKeepsPlainIconButStillShowsReadout() {
    let input = Input(liveStatus: false, isRecording: true, musicPlaying: true, statsReadout: "CPU 12%")
    #expect(MenuBarStatusPolicy.output(input) == .init(icon: .idle, title: "CPU 12%"))
  }

  @Test func timerTitleCountsDownAndMarksPause() {
    #expect(MenuBarStatusPolicy.output(Input(timerRemaining: 65)).title == "1:05")
    #expect(MenuBarStatusPolicy.output(Input(timerRemaining: 3725)).title == "1:02:05")
    #expect(MenuBarStatusPolicy.output(Input(timerRemaining: 30, timerPaused: true)).title == "‖ 0:30")
  }

  @Test func songShowsOnlyWhenAskedAndNotDuplicatedByThePlayerItem() {
    var input = Input(musicPlaying: true, songText: "Kill Bill — SZA", showsSong: true)
    #expect(MenuBarStatusPolicy.output(input).title == "Kill Bill — SZA")
    input.playerItemShowsSong = true
    #expect(MenuBarStatusPolicy.output(input).title == "")
    input.playerItemShowsSong = false
    input.showsSong = false
    #expect(MenuBarStatusPolicy.output(input).title == "")
    input.showsSong = true
    input.musicPlaying = false
    #expect(MenuBarStatusPolicy.output(input).title == "", "a paused song isn't announced")
  }

  @Test func timerWinsOverSongInTheTitleAndReadoutAppends() {
    let input = Input(timerRemaining: 120, musicPlaying: true, songText: "Song", showsSong: true, statsReadout: "RAM 40%")
    #expect(MenuBarStatusPolicy.output(input).title == "2:00 · RAM 40%")
  }

  @Test func readoutFormatsEachKind() {
    func r(_ k: MenuBarStatsReadout) -> String? {
      MenuBarStatusPolicy.readout(k, cpu: 0.256, memory: 0.5, down: 2_400_000, up: 180_000, battery: 82, charging: true)
    }
    #expect(r(.off) == nil)
    #expect(r(.cpu) == "CPU 26%")
    #expect(r(.memory) == "RAM 50%")
    #expect(r(.network) == "↓2.4 MB ↑180 KB")
    #expect(r(.battery) == "82%⚡︎")
    #expect(MenuBarStatusPolicy.readout(.battery, cpu: 0, memory: 0, down: 0, up: 0, battery: nil, charging: false) == nil)
  }
}
