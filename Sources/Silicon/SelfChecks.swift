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
            try expect(decoded["model"] as? String == "Test model", "Export hardware model without a serial number")
            try expect(decoded["os"] as? String == "Test OS", "Export OS version for compatibility reports")
            try expect(decoded["logicalCoreCount"] as? Int == 14, "Export the detected core count")
            try expect(!(decoded["appVersion"] as? String ?? "").isEmpty, "Identify the app build in exported reports")

            // Synthetic SMC responses test selection and handling, not physical
            // calibration. Never load a user's exported process data here.
            func samples(_ chip: String, _ readings: [String: Double]) -> [SensorSample] {
                SensorCatalog.samples(definitions: SensorCatalog.temperatureDefinitions(chip: chip)) { readings[$0] }
            }
            let m2Fixture = ["Tp1h": 41.25, "Tp1l": 43.5, "Tp01": 52.5, "Tp0b": 51.0, "Tg0f": 44.75, "TB0T": 28.0, "F0Ac": 0.0]
            let m2 = samples("Apple M2", m2Fixture)
            let cpuReadings = Dictionary(uniqueKeysWithValues: m2.filter { $0.group == "CPU" }.map { ($0.id, $0.value) })
            try expect(cpuReadings == ["Tp1h": 41.25, "Tp1l": 43.5, "Tp01": 52.5, "Tp0b": 51.0], "Read M2 CPU sensors with case-sensitive hardware keys")
            try expect(m2.first { $0.group == "GPU" }?.value == 44.75, "Read M2 GPU temperature")
            try expect(["Apple M2 Pro", "Apple M2 Max", "Apple M2 Ultra"].allSatisfy { chip in
                let result = samples(chip, m2Fixture)
                return result.contains { $0.group == "CPU" } && result.contains { $0.group == "GPU" }
            }, "Select M2-family mappings for supported chip-name variants")
            let m3 = samples("Apple M3 Max", ["Te05": 41, "Tf04": 50, "Tf14": 45, "Tp01": 99])
            try expect(Set(m3.map(\.id)) == ["Te05", "Tf04", "Tf14"], "Keep M3 CPU/GPU mapping separate from M2")
            try expect(!samples("Apple M20", m2Fixture).contains { $0.group == "CPU" || $0.group == "GPU" }, "Do not guess an unsupported generation from a partial chip name")
            try expect(samples("Intel Core i7", ["TC0P": 37]).first?.value == 37, "Preserve legacy CPU proximity reads")
            let invalidTemperatures: [String: Double] = ["Tp1h": .nan, "Tp1t": .infinity, "Tp1p": 0, "Tp1l": -1, "Tp01": 130, "Tp05": 42]
            try expect(samples("Apple M2", invalidTemperatures).map(\.id) == ["Tp05"], "Reject nonfinite and out-of-range temperature readings")
            let fanReadings: [String: Double] = ["F0Ac": 0, "F1Ac": -1, "F2Ac": .nan, "F3Ac": 15000]
            let fans = samples("Apple M2", fanReadings)
            try expect(fans.count == 1 && fans.first?.id == "F0Ac" && fans.first?.value == 0, "Preserve actual zero RPM while rejecting invalid fan readings")
            let batteryOnly = samples("Apple M2", ["TB0T": 29, "TB1T": 28, "F0Ac": 0])
            try expect(Set(batteryOnly.map(\.group)) == ["Battery", "Fan"], "Never substitute battery temperatures for unavailable CPU/GPU sensors")
            let definitions = SensorCatalog.temperatureDefinitions(chip: "Apple M2")
            var sensorAwake = false
            let read: (String) -> Double? = { key in sensorAwake && key == "Tp01" ? 44 : nil }
            let beforeWake = SensorCatalog.samples(definitions: definitions, read: read)
            sensorAwake = true
            let afterWake = SensorCatalog.samples(definitions: definitions, read: read)
            try expect(beforeWake.isEmpty && afterWake.first?.id == "Tp01" && afterWake.first?.value == 44, "Recover a sensor that was unavailable during the first sample")
            print("PASS: \(count) regression checks.")
            return 0
        } catch { fputs("FAIL: \(error)\n", stderr); return 1 }
    }
}
