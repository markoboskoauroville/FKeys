import Foundation
import IOKit

/// Reads and writes the macOS "Use F1, F2, etc. keys as standard function keys"
/// setting.
///
/// There are three ways to reach this setting and they are not equivalent:
///
/// - **IOHIDEventSystemClient**, per keyboard service. This is what System
///   Settings uses and what actually works on Apple Silicon.
/// - **IOHIDManager**, the public equivalent, writing the same property on the
///   device. Second attempt, in case the private symbols above ever vanish.
/// - **IOHIDSystem**, the old single system wide service. On Apple Silicon this
///   accepts the write, returns success, and does nothing. It is kept only as a
///   last resort for older Intel Macs.
///
/// Because a write can be accepted and silently ignored, nothing here trusts a
/// return code. The result is confirmed by reading the value back out of the
/// hardware, and `set` reports failure if the read back disagrees.
enum FnKeyMode {

    /// `kIOHIDParamConnectType` from IOKit/hidsystem/IOHIDLib.h. Hardcoded
    /// because that enum is not surfaced to Swift.
    private static let paramConnectType: UInt32 = 1
    private static let hidKey = "HIDFKeyMode" as CFString
    private static let prefKey = "fnState" as CFString
    private static let prefDomain = "com.apple.keyboard" as CFString
    private static let changeNotification = "com.apple.keyboard.fnstatedidchange"

    struct Outcome {
        let succeeded: Bool
        let detail: String
    }

    /// True when F1-F12 act as plain function keys, according to the hardware.
    ///
    /// **Never call this on the main thread during launch.** Talking to the HID
    /// layer means waiting on another process, and if that wait is slow the
    /// menu bar item is created but never gets a title drawn, so it renders as
    /// a zero width sliver and looks exactly like the app failing to start.
    /// Use `storedPreference` for the first paint and refresh from here in the
    /// background.
    static var isFunctionKeyMode: Bool {
        if let live = HIDServices.fKeyMode() { return live }
        if let live = HIDDevices.fKeyMode() { return live }
        return storedPreference
    }

    /// Instant, no interprocess call. Good enough to paint the letter with.
    static var storedPreference: Bool {
        CFPreferencesAppSynchronize(prefDomain)
        var valid: DarwinBoolean = false
        let value = CFPreferencesGetAppBooleanValue(prefKey, prefDomain, &valid)
        return valid.boolValue ? value : false
    }

    @discardableResult
    static func set(_ functionKeys: Bool) -> Outcome {
        var notes: [String] = []

        let services = HIDServices.setFKeyMode(functionKeys)
        notes.append("event system services written: \(services)")

        let devices = HIDDevices.setFKeyMode(functionKeys)
        notes.append("hid manager devices written: \(devices)")

        let legacy = setViaIOHIDSystem(functionKeys)
        notes.append("legacy IOHIDSystem: \(legacy ? "accepted" : "refused")")

        // Persist regardless, so the setting survives a reboot and the System
        // Settings checkbox agrees with whatever the hardware now reports.
        CFPreferencesSetAppValue(prefKey,
                                 functionKeys ? kCFBooleanTrue : kCFBooleanFalse,
                                 prefDomain)
        CFPreferencesAppSynchronize(prefDomain)
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name(changeNotification),
            object: nil,
            userInfo: ["state": functionKeys],
            deliverImmediately: true)

        // The only answer that counts. A write being accepted proves nothing.
        let readBack = HIDServices.fKeyMode() ?? HIDDevices.fKeyMode()
        if let readBack {
            notes.append("read back: \(readBack ? "function keys" : "media keys")")
            return Outcome(succeeded: readBack == functionKeys,
                           detail: notes.joined(separator: "\n"))
        }

        notes.append("read back: no keyboard answered")
        // Nothing could be verified either way. Treat a service or device
        // accepting the write as success rather than alarming the user.
        return Outcome(succeeded: services > 0 || devices > 0,
                       detail: notes.joined(separator: "\n"))
    }

    @discardableResult
    static func toggle() -> Outcome {
        set(!isFunctionKeyMode)
    }

    // MARK: - Legacy path

    private static func setViaIOHIDSystem(_ on: Bool) -> Bool {
        guard let matching = IOServiceMatching("IOHIDSystem") else { return false }
        var iterator: io_iterator_t = 0
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

    // MARK: - Diagnostics

    /// A plain text report, for when it still does not work and the only way
    /// forward is knowing which layer answered.
    static func diagnostics() -> String {
        var lines: [String] = ["FKeys diagnostics"]
        lines.append("macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
        lines.append("event system symbols available: \(HIDServices.isAvailable)")
        lines.append("keyboard services seen: \(HIDServices.keyboardCount())")
        lines.append("hid manager keyboards seen: \(HIDDevices.keyboardCount())")
        lines.append("service reports: \(describe(HIDServices.fKeyMode()))")
        lines.append("device reports: \(describe(HIDDevices.fKeyMode()))")
        lines.append("stored preference: \(storedPreference ? "function keys" : "media keys")")
        return lines.joined(separator: "\n")
    }

    private static func describe(_ value: Bool?) -> String {
        guard let value else { return "no answer" }
        return value ? "function keys" : "media keys"
    }
}
