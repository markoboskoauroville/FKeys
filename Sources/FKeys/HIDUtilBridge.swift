import Foundation

/// Sets the property through Apple's own `/usr/bin/hidutil`.
///
/// This is the route Apple documents in Technical Note TN2450 for HID service
/// properties. It runs in a separate process, so however badly it goes it
/// cannot take FKeys down with it. That makes it the first thing to try, ahead
/// of anything that runs inside this process.
enum HIDUtilBridge {

    static var isAvailable: Bool {
        FileManager.default.isExecutableFile(atPath: "/usr/bin/hidutil")
    }

    /// - Returns: the tool's own output, or nil when it could not be run.
    @discardableResult
    static func setFKeyMode(_ on: Bool) -> String? {
        run(["property", "--set", "{\"HIDFKeyMode\":\(on ? 1 : 0)}"])
    }

    static func readFKeyMode() -> Bool? {
        guard let output = run(["property", "--get", "\"HIDFKeyMode\""]) else { return nil }
        // Output is a plist-ish dump. Anything conclusive will contain the key
        // followed by a number, so pull the first digit after it.
        guard let range = output.range(of: "HIDFKeyMode") else { return nil }
        let tail = output[range.upperBound...]
        for character in tail {
            if character == "0" { return false }
            if character == "1" { return true }
            if character.isNewline { break }
        }
        return nil
    }

    private static func run(_ arguments: [String]) -> String? {
        guard isAvailable else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }
}
