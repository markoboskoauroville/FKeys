import Foundation
import IOKit
import IOKit.hid

/// Access to the per keyboard HID services through `IOHIDEventSystemClient`.
///
/// This is the layer System Settings itself uses. Apple's Technical Note TN2450
/// points developers at `IOHIDEventSystemClient` for exactly this kind of
/// keyboard property work, but the symbols are not in any public header, so
/// they are resolved by name at runtime. If a future macOS removes them,
/// `isAvailable` goes false and the caller falls back rather than crashing.
enum HIDServices {

    private typealias CreateSimpleClient =
        @convention(c) (CFAllocator?) -> Unmanaged<CFTypeRef>?
    private typealias CopyServices =
        @convention(c) (CFTypeRef) -> Unmanaged<CFArray>?
    private typealias ServiceSetProperty =
        @convention(c) (CFTypeRef, CFString, CFTypeRef) -> Bool
    private typealias ServiceCopyProperty =
        @convention(c) (CFTypeRef, CFString) -> Unmanaged<CFTypeRef>?
    private typealias ServiceConformsTo =
        @convention(c) (CFTypeRef, UInt32, UInt32) -> Bool

    private static func symbol<T>(_ name: String, as type: T.Type) -> T? {
        guard let pointer = dlsym(UnsafeMutableRawPointer(bitPattern: -2), name) else { return nil }
        return unsafeBitCast(pointer, to: type)
    }

    private static let createClient =
        symbol("IOHIDEventSystemClientCreateSimpleClient", as: CreateSimpleClient.self)
    private static let copyServices =
        symbol("IOHIDEventSystemClientCopyServices", as: CopyServices.self)
    private static let setProperty =
        symbol("IOHIDServiceClientSetProperty", as: ServiceSetProperty.self)
    private static let copyProperty =
        symbol("IOHIDServiceClientCopyProperty", as: ServiceCopyProperty.self)
    private static let conformsTo =
        symbol("IOHIDServiceClientConformsTo", as: ServiceConformsTo.self)

    static var isAvailable: Bool {
        !HIDSafety.privatePathDisabled
            && createClient != nil && copyServices != nil && setProperty != nil
    }

    /// Keyboard services only: usage page 1 (generic desktop), usage 6 (keyboard).
    ///
    /// Every entry point into the private symbols goes through HIDSafety, so a
    /// crash in here disables this whole path on the next launch instead of
    /// leaving an app that cannot start.
    private static func keyboardServices() -> [CFTypeRef] {
        HIDSafety.guarded(fallback: []) { unguardedKeyboardServices() }
    }

    private static func unguardedKeyboardServices() -> [CFTypeRef] {
        guard !HIDSafety.privatePathDisabled,
              let createClient, let copyServices,
              let client = createClient(kCFAllocatorDefault)?.takeRetainedValue(),
              let all = copyServices(client)?.takeRetainedValue() as? [CFTypeRef]
        else { return [] }

        guard let conformsTo else { return all }
        return all.filter { conformsTo($0, 1, 6) }
    }

    /// - Returns: how many keyboard services accepted the write.
    @discardableResult
    static func setFKeyMode(_ on: Bool) -> Int {
        guard let setProperty else { return 0 }
        var raw: Int32 = on ? 1 : 0
        guard let number = CFNumberCreate(kCFAllocatorDefault, .sInt32Type, &raw) else { return 0 }

        var accepted = 0
        for service in keyboardServices() where setProperty(service, "HIDFKeyMode" as CFString, number) {
            accepted += 1
        }
        return accepted
    }

    /// The value the hardware actually holds, or nil when nothing could be read.
    /// This is the only honest source of truth: a write can be accepted and
    /// then ignored, so the answer has to be read back.
    static func fKeyMode() -> Bool? {
        guard let copyProperty else { return nil }
        for service in keyboardServices() {
            guard let value = copyProperty(service, "HIDFKeyMode" as CFString)?.takeRetainedValue(),
                  let number = value as? NSNumber else { continue }
            return number.intValue != 0
        }
        return nil
    }

    static func keyboardCount() -> Int { keyboardServices().count }
}

/// The same property, reached through the public `IOHIDManager` instead.
/// Kept as a second attempt because the private symbols above could disappear.
///
/// The manager is deliberately never opened. Enumerating devices needs no
/// permission; `IOHIDManagerOpen` would trigger the Input Monitoring prompt,
/// which would cost FKeys its one real advantage.
enum HIDDevices {

    private static func keyboards() -> [IOHIDDevice] {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let match: [String: Any] = [
            kIOHIDDeviceUsagePageKey: 0x01,
            kIOHIDDeviceUsageKey: 0x06
        ]
        IOHIDManagerSetDeviceMatching(manager, match as CFDictionary)
        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return [] }
        return Array(devices)
    }

    @discardableResult
    static func setFKeyMode(_ on: Bool) -> Int {
        var raw: Int32 = on ? 1 : 0
        guard let number = CFNumberCreate(kCFAllocatorDefault, .sInt32Type, &raw) else { return 0 }
        var accepted = 0
        for device in keyboards()
        where IOHIDDeviceSetProperty(device, "HIDFKeyMode" as CFString, number) {
            accepted += 1
        }
        return accepted
    }

    static func fKeyMode() -> Bool? {
        for device in keyboards() {
            guard let value = IOHIDDeviceGetProperty(device, "HIDFKeyMode" as CFString),
                  let number = value as? NSNumber else { continue }
            return number.intValue != 0
        }
        return nil
    }

    static func keyboardCount() -> Int { keyboards().count }
}
