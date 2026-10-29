import AppKit

/// Puts a window above the lock screen. Isolated behind a protocol so the rest of the feature,
/// and its tests, never touch private symbols.
@MainActor
protocol LockScreenWindowBridge: AnyObject {
    /// False when SkyLight or one of the symbols we need is missing on this macOS.
    var isAvailable: Bool { get }
    /// Moves the window into the lock-screen space. Returns false when it could not.
    func delegate(_ window: NSWindow) -> Bool
    /// True while the window is still composited in our space; nil when the system can't tell us.
    func isDelegated(_ window: NSWindow) -> Bool?
    /// Re-applies the space's level and shows it again. Called after display wake, when the window
    /// server may have rebuilt its space list.
    func reassert()
    /// Hides the lock-screen space and removes our windows from it.
    func teardown()
}

/// The handful of SkyLight calls the bridge makes, as a protocol so tests can record them.
protocol SkyLightSpaceAPI: AnyObject {
    func mainConnection() -> Int32
    func createSpace(connection: Int32) -> Int32
    func setAbsoluteLevel(connection: Int32, space: Int32, level: Int32)
    func showSpaces(connection: Int32, _ spaces: [Int32])
    func hideSpaces(connection: Int32, _ spaces: [Int32])
    /// Moves windows into `space`, removing them from every other space.
    func addWindows(connection: Int32, space: Int32, windows: [Int]) -> Bool
    /// The spaces each window is in, or nil when the lookup symbol is missing.
    func spaces(connection: Int32, windows: [Int]) -> [Int]?
    func destroySpace(connection: Int32, space: Int32)
}

/// Window-server space delegation, the technique also used by Lakr233's MIT-licensed
/// SkyLightWindow package: create a private space, give it the absolute level that sits above the
/// lock screen, show it, and move windows into it. This is our own implementation; every symbol is
/// resolved at runtime and a missing one disables the bridge instead of crashing.
@MainActor
final class SkyLightBridge: LockScreenWindowBridge {
    /// `kSLSSpaceAbsoluteLevelNotificationCenterAtScreenLock`.
    static let notificationCenterAtScreenLockLevel: Int32 = 400

    private let api: SkyLightSpaceAPI?
    private var connection: Int32 = 0
    private(set) var space: Int32 = 0

    var isAvailable: Bool { api != nil }

    init(api: SkyLightSpaceAPI? = LiveSkyLightAPI.load()) { self.api = api }

    /// Creates the space on first use so merely launching the app never touches the window server.
    private func readyAPI() -> SkyLightSpaceAPI? {
        guard let api else { return nil }
        if space == 0 {
            connection = api.mainConnection()
            space = api.createSpace(connection: connection)
            guard space != 0 else { return nil }
            api.setAbsoluteLevel(connection: connection, space: space, level: Self.notificationCenterAtScreenLockLevel)
            api.showSpaces(connection: connection, [space])
        }
        return api
    }

    func delegate(_ window: NSWindow) -> Bool {
        guard window.windowNumber > 0, let api = readyAPI() else { return false }
        return api.addWindows(connection: connection, space: space, windows: [window.windowNumber])
    }

    func isDelegated(_ window: NSWindow) -> Bool? {
        guard window.windowNumber > 0, space != 0,
              let spaces = api?.spaces(connection: connection, windows: [window.windowNumber])
        else { return nil }
        return spaces.contains(Int(space))
    }

    func reassert() {
        guard let api, space != 0 else { return }
        api.setAbsoluteLevel(connection: connection, space: space, level: Self.notificationCenterAtScreenLockLevel)
        api.showSpaces(connection: connection, [space])
    }

    func teardown() {
        guard let api, space != 0 else { return }
        api.hideSpaces(connection: connection, [space])
        api.destroySpace(connection: connection, space: space)
        space = 0
    }
}

/// The real SkyLight functions, resolved with `dlsym`. `load()` returns nil when the framework or a
/// required symbol is missing.
final class LiveSkyLightAPI: SkyLightSpaceAPI {
    private static let skyLightPath = "/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight"
    /// `SLSSpaceAddWindowsAndRemoveFromSpaces` option: remove from all current/other/user spaces.
    static let addWindowsMask: Int32 = 7
    /// `SLSCopySpacesForWindows` selector. 7 only lists desktop (user) spaces; the 0x8 bit is needed
    /// to see our own overlay space (verified on macOS 27: mask 7 returns [] for a delegated window,
    /// mask 15 returns the overlay space id). With 7 the watchdog thought every window was lost.
    static let spaceLookupMask: Int32 = 15

    private typealias MainConnection = @convention(c) () -> Int32
    private typealias SpaceCreate = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias SpaceSetLevel = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias SpacesCall = @convention(c) (Int32, CFArray) -> Int32
    private typealias AddWindows = @convention(c) (Int32, Int32, CFArray, Int32) -> Int32
    private typealias SpacesForWindows = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?
    private typealias SpaceDestroy = @convention(c) (Int32, Int32) -> Int32

    private let main: MainConnection
    private let create: SpaceCreate
    private let level: SpaceSetLevel
    private let show: SpacesCall
    private let add: AddWindows
    private let hide: SpacesCall?
    private let lookup: SpacesForWindows?
    private let destroy: SpaceDestroy?

    private init(main: MainConnection, create: SpaceCreate, level: SpaceSetLevel, show: SpacesCall, add: AddWindows,
                 hide: SpacesCall?, lookup: SpacesForWindows?, destroy: SpaceDestroy?) {
        self.main = main
        self.create = create
        self.level = level
        self.show = show
        self.add = add
        self.hide = hide
        self.lookup = lookup
        self.destroy = destroy
    }

    static func load() -> LiveSkyLightAPI? {
        guard let handle = dlopen(skyLightPath, RTLD_NOW) else { return nil }
        func symbol<T>(_ name: String, as _: T.Type) -> T? {
            guard let raw = dlsym(handle, name) else { return nil }
            return unsafeBitCast(raw, to: T.self)
        }
        guard let main = symbol("SLSMainConnectionID", as: MainConnection.self),
              let create = symbol("SLSSpaceCreate", as: SpaceCreate.self),
              let level = symbol("SLSSpaceSetAbsoluteLevel", as: SpaceSetLevel.self),
              let show = symbol("SLSShowSpaces", as: SpacesCall.self),
              let add = symbol("SLSSpaceAddWindowsAndRemoveFromSpaces", as: AddWindows.self)
        else { return nil }
        return LiveSkyLightAPI(
            main: main, create: create, level: level, show: show, add: add,
            hide: symbol("SLSHideSpaces", as: SpacesCall.self),
            lookup: symbol("SLSCopySpacesForWindows", as: SpacesForWindows.self),
            destroy: symbol("SLSSpaceDestroy", as: SpaceDestroy.self))
    }

    func mainConnection() -> Int32 { main() }
    func createSpace(connection: Int32) -> Int32 { create(connection, 1, 0) }
    func setAbsoluteLevel(connection: Int32, space: Int32, level value: Int32) { _ = level(connection, space, value) }
    func showSpaces(connection: Int32, _ spaces: [Int32]) { _ = show(connection, spaces as CFArray) }
    func hideSpaces(connection: Int32, _ spaces: [Int32]) { _ = hide?(connection, spaces as CFArray) }

    /// `SLSSpaceAddWindowsAndRemoveFromSpaces` returns no meaningful status on current macOS (it
    /// returned 3 on a call that worked), so success is "the call was made".
    func addWindows(connection: Int32, space: Int32, windows: [Int]) -> Bool {
        _ = add(connection, space, windows as CFArray, Self.addWindowsMask)
        return true
    }

    func spaces(connection: Int32, windows: [Int]) -> [Int]? {
        guard let lookup else { return nil }
        return lookup(connection, Self.spaceLookupMask, windows as CFArray)?.takeRetainedValue() as? [Int] ?? []
    }

    func destroySpace(connection: Int32, space: Int32) { _ = destroy?(connection, space) }
}
