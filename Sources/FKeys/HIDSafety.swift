import Foundation

/// A per stage crash fuse.
///
/// Several different layers can be asked to change the function key mode, and
/// any one of them may trap on a given macOS. A flag naming the stage about to
/// run is forced to disk before entering it and cleared immediately after. If a
/// stage name is still on disk at the next launch, that stage killed the app
/// last time, so it is disabled permanently and the others carry on.
///
/// The earlier version guarded only the enumeration and not the write, so the
/// flag was always cleared before the fatal call and the fuse could never trip.
/// Every call into a risky layer now goes through `guarded`.
enum HIDSafety {
    private static let inFlightKey = "hid.stageInFlight"
    private static let disabledKey = "hid.disabledStages"
    private static let defaults = UserDefaults.standard

    enum Stage: String, CaseIterable {
        case hidutilWrite      = "hidutil.write"
        case devicesEnumerate  = "devices.enumerate"
        case devicesWrite      = "devices.write"
        case devicesRead       = "devices.read"
        case servicesEnumerate = "services.enumerate"
        case servicesWrite     = "services.write"
        case servicesRead      = "services.read"
        case legacyWrite       = "legacy.write"
    }

    static var disabledStages: Set<String> {
        Set(defaults.stringArray(forKey: disabledKey) ?? [])
    }

    static func isDisabled(_ stage: Stage) -> Bool {
        disabledStages.contains(stage.rawValue)
    }

    /// Call once, first thing at launch, before anything touches HID.
    static func inspectPreviousRun() {
        guard let stage = defaults.string(forKey: inFlightKey), !stage.isEmpty else { return }
        var disabled = disabledStages
        disabled.insert(stage)
        defaults.set(Array(disabled).sorted(), forKey: disabledKey)
        defaults.removeObject(forKey: inFlightKey)
        defaults.synchronize()
        NSLog("FKeys: stage \(stage) killed the previous launch, disabling it")
    }

    static func guarded<T>(_ stage: Stage, fallback: T, _ work: () -> T) -> T {
        guard !isDisabled(stage) else { return fallback }
        defaults.set(stage.rawValue, forKey: inFlightKey)
        // Forced to disk now: the whole point is surviving a hard crash on the
        // very next line.
        defaults.synchronize()
        let result = work()
        defaults.removeObject(forKey: inFlightKey)
        defaults.synchronize()
        return result
    }

    static func reset() {
        defaults.removeObject(forKey: disabledKey)
        defaults.removeObject(forKey: inFlightKey)
        defaults.synchronize()
    }

    static var report: String {
        let disabled = disabledStages
        guard !disabled.isEmpty else { return "no stages disabled" }
        return "disabled after crashing: " + disabled.sorted().joined(separator: ", ")
    }
}
