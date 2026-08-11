import Foundation

/// The state FKeys manages: are F1 to F12 plain function keys, or the printed
/// media and brightness controls.
///
/// This does **not** touch `com.apple.keyboard.fnState`, the setting behind the
/// System Settings checkbox. That setting is unreachable on Apple Silicon: the
/// old IOHIDSystem call accepts it and does nothing, hidutil has no such
/// property, and the private event system call kills the process. Key
/// remapping is the mechanism Apple documents, and it works.
///
/// The visible consequence is that the System Settings checkbox stays unticked
/// while the keyboard behaves as though it were ticked. That is expected.
enum FnKeyMode {

    private static let desiredKey = "fkeys.functionMode"
    private static let defaults = UserDefaults.standard

    struct Outcome {
        let succeeded: Bool
        let detail: String
    }

    /// What the user last asked for. Survives quitting and rebooting.
    static var desiredFunctionKeys: Bool {
        get { defaults.bool(forKey: desiredKey) }
        set { defaults.set(newValue, forKey: desiredKey) }
    }

    /// Whether the mapping is live right now, read back from hidutil rather
    /// than assumed. Cheap: one short subprocess.
    static var isFunctionKeyMode: Bool {
        guard let mapping = Hidutil.currentUserKeyMapping() else { return false }
        return mapping.contains("HIDKeyboardModifierMappingSrc")
    }

    @discardableResult
    static func set(_ functionKeys: Bool) -> Outcome {
        desiredFunctionKeys = functionKeys

        let output = functionKeys
            ? Hidutil.setUserKeyMapping(FnKeyMap.swapJSON())
            : Hidutil.clearUserKeyMapping()

        guard output != nil else {
            return Outcome(succeeded: false, detail: "hidutil could not be run")
        }

        // Confirm against the system rather than trusting the write. The old
        // implementation trusted a success code and was wrong for days.
        let live = isFunctionKeyMode
        return Outcome(succeeded: live == functionKeys,
                       detail: "requested \(functionKeys ? "function keys" : "media keys"), "
                              + "system reports \(live ? "function keys" : "media keys")")
    }

    @discardableResult
    static func toggle() -> Outcome {
        set(!isFunctionKeyMode)
    }

    /// Key remapping is cleared by a reboot, and by the last keyboard being
    /// disconnected. Called at launch and after waking so the choice sticks
    /// without the user having to think about it.
    static func reapplyIfNeeded() {
        guard desiredFunctionKeys, !isFunctionKeyMode else { return }
        _ = Hidutil.setUserKeyMapping(FnKeyMap.swapJSON())
    }

    static func diagnostics() -> String {
        var lines = ["FKeys diagnostics"]
        lines.append("macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
        lines.append("hidutil present: \(Hidutil.isAvailable)")
        lines.append("keyboard map: \(FnKeyMap.usedFallback ? "built in fallback" : "read from this Mac")")
        lines.append("pairs found: \(FnKeyMap.pairs().count)")
        lines.append("mapping active: \(isFunctionKeyMode)")
        lines.append("last requested: \(desiredFunctionKeys ? "function keys" : "media keys")")
        return lines.joined(separator: "\n")
    }
}
