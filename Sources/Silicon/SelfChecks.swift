import Foundation

// A dependency-free regression runner, since Command Line Tools do not include
// XCTest. These exercise parsing and missing-data cases without opening the UI.
enum SelfChecks {
    private struct Failure: Error, CustomStringConvertible { let description: String }
    static func run() -> Int32 {
        var count = 0
        func expect(_ condition: @autoclosure () -> Bool, _ description: String) throws {
            guard condition() else { throw Failure(description: description) }
            count += 1
        }
        do {
            let input = "  105  245.3  2048 /Applications/Example App.app/Contents/MacOS/Example App\n  6 0.0 0 /sbin/launchd\ninvalid row\n"
            let parsed = Collector.parseProcesses(input)
            try expect(parsed.count == 2, "Ignore malformed process rows")
            try expect(parsed[0].name == "Example App", "Preserve process names with spaces")
            try expect(parsed[0].path == "/Applications/Example App.app/Contents/MacOS/Example App", "Preserve executable paths with spaces")
            try expect(parsed[0].cpu == 245.3, "Preserve multi-core CPU usage above 100 percent")
            try expect(parsed[0].memory == 2_097_152, "Convert process RSS from KiB to bytes")
            try expect(parsed[1].memory == 0, "Accept zero-memory processes")
            let invalid = Collector.parseProcesses("1 nan 25 /bin/test\n2 -1.0 25 /bin/test\n3 1.0 -2 /bin/test\n4 1.2 40 /bin/valid")
            try expect(invalid.map(\.id) == [4], "Reject invalid numeric process readings")
            let memory = MemorySample(total: 100, app: 70, wired: 20, compressed: 30)
            try expect(memory.used == 100 && memory.available == 0 && memory.percent == 100, "Clamp racing memory counters to physical capacity")
            try expect(MemorySample(pressure: 0).pressureLabel == "Unavailable", "Do not report missing pressure as normal")
            try expect(MemorySample(pressure: 1).pressureLabel == "Normal", "Interpret normal kernel pressure")
            try expect(MemorySample(pressure: 4).pressureLabel == "Critical", "Interpret critical kernel pressure")
            try expect(Format.temperature(nil) == "—", "Do not invent unavailable temperatures")
            try expect(Format.temperature(40, fahrenheit: true) == "104°F", "Convert Fahrenheit readouts")
            try expect(Format.temperature(40) == "40°C", "Retain Celsius readouts")
            let machine = MachineInfo(chip: "Test chip", model: "Test model", cores: 14, performanceCores: 10, efficiencyCores: 4, memory: 1024, os: "Test OS")
            let snapshot = try SnapshotEncoder.encode(date: Date(timeIntervalSince1970: 0), machine: machine, cpu: CPUSample(user: 20, system: 10), memory: memory, thermal: "Nominal", sensors: [SensorSample(id: "F0Ac", name: "Fan 1", group: "Fan", value: 0)], processes: parsed)
            let decoded = try JSONSerialization.jsonObject(with: snapshot) as! [String: Any]
            try expect(decoded["cpuPercent"] as? Double == 30, "Export combined CPU usage as numeric JSON")
            try expect((decoded["processes"] as? [[String: Any]])?.count == 2, "Export every process")
            try expect(!(String(data: snapshot, encoding: .utf8) ?? "").contains("/Applications/"), "Exclude executable paths from exports")
            try expect((decoded["sensors"] as? [[String: Any]])?.first?["unit"] as? String == "RPM", "Export explicit sensor units")
            print("PASS: \(count) regression checks.")
            return 0
        } catch { fputs("FAIL: \(error)\n", stderr); return 1 }
    }
}
