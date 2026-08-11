import Foundation
import IOKit

/// Reads and writes the macOS "Use F1, F2, etc. keys as standard function keys"
/// setting.
///
/// Three things have to happen for a change to be real and to stick:
///
/// 1. `IOConnectSetCFProperty` on the IOHIDSystem service applies it to the
///    hardware immediately. Writing the preference alone does nothing until the
///    next login, which is why `defaults write com.apple.keyboard.fnState`
///    appears not to work.
/// 2. `CFPreferences` persists it, so it survives a reboot and so the System
///    Settings checkbox agrees with reality.
/// 3. The distributed notification tells anything already running, System
///    Settings included, to re-read the value.
///
/// None of this needs Accessibility permission or root. It is the same route
/// Fluor and fntoggle take, rather than AppleScript clicking a checkbox, which
/// only works on an English system and breaks whenever Apple moves the pane.
enum FnKeyMode {

    /// `kIOHIDParamConnectType` from IOKit/hidsystem/IOHIDLib.h. Hardcoded
    /// because that enum is not surfaced to Swift.
    private static let paramConnectType: UInt32 = 1
    private static let hidKey = "HIDFKeyMode" as CFString
    private static let prefKey = "fnState" as CFString
    private static let prefDomain = "com.apple.keyboard" as CFString
    private static let changeNotification = "com.apple.keyboard.fnstatedidchange"

    /// True when F1-F12 act as plain function keys.
    /// False when they act as the printed media and brightness controls.
    static var isFunctionKeyMode: Bool {
        CFPreferencesAppSynchronize(prefDomain)
        var valid: DarwinBoolean = false
        let value = CFPreferencesGetAppBooleanValue(prefKey, prefDomain, &valid)
        return valid.boolValue ? value : false
    }

    @discardableResult
    static func set(_ functionKeys: Bool) -> Bool {
        guard applyToHardware(functionKeys) else { return false }

        CFPreferencesSetAppValue(prefKey,
                                 functionKeys ? kCFBooleanTrue : kCFBooleanFalse,
                                 prefDomain)
        CFPreferencesAppSynchronize(prefDomain)

        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name(changeNotification),
            object: nil,
            userInfo: ["state": functionKeys],
            deliverImmediately: true)

        return true
    }

    @discardableResult
    static func toggle() -> Bool {
        set(!isFunctionKeyMode)
    }

    private static func applyToHardware(_ on: Bool) -> Bool {
        guard let matching = IOServiceMatching("IOHIDSystem") else { return false }

        var iterator: io_iterator_t = 0
        // IOServiceGetMatchingServices consumes the matching dictionary.
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS
        else { return false }
        defer { IOObjectRelease(iterator) }

        let service = IOIteratorNext(iterator)
        guard service != 0 else { return false }
        defer { IOObjectRelease(service) }

        var connect: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, paramConnectType, &connect) == KERN_SUCCESS
        else { return false }
        defer { IOServiceClose(connect) }

        var raw: Int32 = on ? 1 : 0
        guard let number = CFNumberCreate(kCFAllocatorDefault, .sInt32Type, &raw) else { return false }

        return IOConnectSetCFProperty(connect, hidKey, number) == KERN_SUCCESS
    }
}
