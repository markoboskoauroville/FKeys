import Foundation

/// Thin wrapper around `/usr/bin/hidutil`.
///
/// Everything FKeys does to the keyboard goes through this. hidutil is Apple's
/// own tool, documented in Technical Note TN2450 for exactly this kind of key
/// remapping, and it runs in a separate process, so no failure inside it can
/// take FKeys down. That is the whole reason this file exists: the previous
/// implementation called undocumented IOKit functions in process and they
/// killed the app on every click.
enum Hidutil {

    static var isAvailable: Bool {
        FileManager.default.isExecutableFile(atPath: "/usr/bin/hidutil")
    }

    @discardableResult
    static func run(_ arguments: [String]) -> String? {
        guard isAvailable else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }

    /// Replaces the whole user key mapping table.
    ///
    /// **This overwrites any other mapping set through hidutil**, by anything.
    /// hidutil replaces the table rather than merging into it, so a mapping set
    /// by another tool is lost when FKeys writes.
    @discardableResult
    static func setUserKeyMapping(_ json: String) -> String? {
        // This argument keeps its quotes: hidutil genuinely wants a JSON
        // object here, and in a terminal the single quotes around it are the
        // shell's, not part of the value.
        run(["property", "--set", "{\"UserKeyMapping\":\(json)}"])
    }

    static func clearUserKeyMapping() -> String? {
        setUserKeyMapping("[]")
    }

    /// nil when nothing is mapped. hidutil prints "(null)" in that case.
    ///
    /// The key name is passed **bare**. In a terminal you write
    /// `hidutil property --get "UserKeyMapping"` and the shell strips those
    /// quotes before hidutil ever sees them. Process runs the binary directly
    /// with no shell, so quoting it here hands hidutil a key called
    /// `"UserKeyMapping"` including the quote characters, which matches
    /// nothing. It answers (null) and the app concludes the write failed.
    static func currentUserKeyMapping() -> String? {
        guard let output = run(["property", "--get", "UserKeyMapping"]) else { return nil }
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.contains("(null)") { return nil }
        return trimmed
    }
}
