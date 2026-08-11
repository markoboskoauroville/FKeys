import Foundation

/// A crash fuse around the private HID calls.
///
/// `HIDServices` resolves undocumented symbols by name and calls them. That is
/// the only route that actually works on Apple Silicon, but it is exactly the
/// kind of code that can take the whole process down on some future macOS, and
/// a menu bar app that dies at launch leaves the user with nothing to click and
/// no way to fix it.
///
/// So: a flag is written to disk immediately before entering that code and
/// cleared immediately after. If the flag is still set at the next launch, the
/// app did not survive the last attempt, and the private path is switched off
/// permanently in favour of the public one. Worst case it crashes once and then
/// heals itself.
enum HIDSafety {
    private static let inFlightKey = "hid.privateProbeInFlight"
    private static let disabledKey = "hid.privateDisabled"
    private static let defaults = UserDefaults.standard

    static var privatePathDisabled: Bool { defaults.bool(forKey: disabledKey) }

    /// Call once, first thing, before anything touches HID.
    static func inspectPreviousRun() {
        guard defaults.bool(forKey: inFlightKey) else { return }
        defaults.set(true, forKey: disabledKey)
        defaults.set(false, forKey: inFlightKey)
        NSLog("FKeys: previous launch died inside the private HID path, disabling it")
    }

    /// Runs `work` with the fuse armed. Returns `fallback` without running
    /// anything once the path has been disabled.
    static func guarded<T>(fallback: T, _ work: () -> T) -> T {
        guard !privatePathDisabled else { return fallback }
        defaults.set(true, forKey: inFlightKey)
        // Forced to disk now, because the point is surviving a hard crash on
        // the very next line.
        defaults.synchronize()
        let result = work()
        defaults.set(false, forKey: inFlightKey)
        defaults.synchronize()
        return result
    }

    static func reenable() {
        defaults.set(false, forKey: disabledKey)
        defaults.set(false, forKey: inFlightKey)
    }
}
