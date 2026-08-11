import Foundation

/// Builds the remapping that turns the top row into plain function keys.
///
/// macOS exposes, per keyboard, a table called `FnFunctionUsageMap`. It pairs
/// each top row key's "with fn" code against its "pressed alone" code. On this
/// machine F1 alone sends brightness down and with fn sends F1, and so on.
///
/// Swapping every pair in both directions gives exactly the behaviour the
/// System Settings checkbox is supposed to give: F1 to F12 alone, media and
/// brightness on fn. Unlike that checkbox this actually takes effect, because
/// key remapping is the one keyboard mechanism Apple documents and supports.
enum FnKeyMap {

    struct Entry {
        let source: UInt64
        let destination: UInt64
    }

    /// The standard modern Apple layout, used when the live table cannot be
    /// read. Macs with a Touch Bar publish no table at all.
    private static let fallbackPairs: [(UInt32, UInt32)] = [
        (0x0007003a, 0x00ff0005), (0x0007003b, 0x00ff0004),
        (0x0007003c, 0xff010010), (0x0007003d, 0x000c0221),
        (0x0007003e, 0x000c00cf), (0x0007003f, 0x0001009b),
        (0x00070040, 0x000c00b4), (0x00070041, 0x000c00cd),
        (0x00070042, 0x000c00b3), (0x00070043, 0x000c00e2),
        (0x00070044, 0x000c00ea), (0x00070045, 0x000c00e9)
    ]

    /// hidutil wants 64 bit values: upper 32 bits the HID page, lower 32 the
    /// usage. The table publishes them packed into 32 bits, so they have to be
    /// unpacked and widened. Getting this wrong is silent: hidutil accepts the
    /// number and nothing happens.
    static func widen(_ packed: UInt32) -> UInt64 {
        let page = UInt64((packed >> 16) & 0xFFFF)
        let usage = UInt64(packed & 0xFFFF)
        return (page << 32) | usage
    }

    private static var cachedPairs: [(UInt32, UInt32)]?

    /// Reads this Mac's own table, so the mapping is correct on any model
    /// rather than only the one it was written on.
    static func pairs() -> [(fnCode: UInt32, plainCode: UInt32)] {
        if let cachedPairs { return cachedPairs.map { (fnCode: $0.0, plainCode: $0.1) } }

        let parsed = readLiveTable() ?? fallbackPairs
        cachedPairs = parsed
        return parsed.map { (fnCode: $0.0, plainCode: $0.1) }
    }

    static var usedFallback: Bool { readLiveTable() == nil }

    private static func readLiveTable() -> [(UInt32, UInt32)]? {
        // -k narrows the registry dump to objects carrying this key, which
        // keeps a full ioreg dump out of memory.
        let output = shell("/usr/sbin/ioreg", ["-l", "-w", "0", "-k", "FnFunctionUsageMap"])
            ?? shell("/usr/sbin/ioreg", ["-l", "-w", "0"])
        guard let output else { return nil }

        guard let line = output.split(separator: "\n").first(where: { $0.contains("FnFunctionUsageMap") }),
              let start = line.range(of: "= \""),
              let end = line.range(of: "\"", range: start.upperBound..<line.endIndex)
        else { return nil }

        let body = line[start.upperBound..<end.lowerBound]
        let values = body.split(separator: ",").compactMap { token -> UInt32? in
            let text = token.trimmingCharacters(in: .whitespaces)
                            .replacingOccurrences(of: "0x", with: "")
            return UInt32(text, radix: 16)
        }
        guard values.count >= 2, values.count % 2 == 0 else { return nil }
        return stride(from: 0, to: values.count, by: 2).map { (values[$0], values[$0 + 1]) }
    }

    /// Both directions: pressed alone gives the function key, held with fn
    /// gives back the printed control.
    static func swapEntries() -> [Entry] {
        var entries: [Entry] = []
        for pair in pairs() {
            let functionKey = widen(pair.fnCode)
            let printed = widen(pair.plainCode)
            entries.append(Entry(source: printed, destination: functionKey))
            entries.append(Entry(source: functionKey, destination: printed))
        }
        return entries
    }

    static func swapJSON() -> String {
        let body = swapEntries().map {
            "{\"HIDKeyboardModifierMappingSrc\":0x\(String($0.source, radix: 16)),"
            + "\"HIDKeyboardModifierMappingDst\":0x\(String($0.destination, radix: 16))}"
        }.joined(separator: ",")
        return "[\(body)]"
    }

    private static func shell(_ path: String, _ arguments: [String]) -> String? {
        guard FileManager.default.isExecutableFile(atPath: path) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }
}
