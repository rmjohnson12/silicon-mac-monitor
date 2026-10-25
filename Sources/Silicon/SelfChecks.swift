import Foundation
import SensorBridge

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
            let m1Fixture = ["Tp09": 39.5, "Tp0T": 40.0, "Tp01": 48.25, "Tp0b": 49.0,
                             "Tg05": 43.0, "Tg0D": 44.0, "Tg0L": 45.0, "Tg0T": 46.0,
                             "Tp1h": 99.0, "Tg0f": 99.0, "TB0T": 28.1, "TB1T": 28.1]
            let m1 = samples("Apple M1", m1Fixture)
            try expect(Dictionary(uniqueKeysWithValues: m1.filter { $0.group == "CPU" }.map { ($0.id, $0.value) }) ==
                       ["Tp09": 39.5, "Tp0T": 40, "Tp01": 48.25, "Tp0b": 49], "Read M1 CPU sensors including case-sensitive suffixes")
            try expect(Set(m1.filter { $0.group == "GPU" }.map(\.id)) == ["Tg05", "Tg0D", "Tg0L", "Tg0T"], "Read M1 GPU sensors without using M2-only keys")
            try expect(["Apple M1 Pro", "Apple M1 Max", "Apple M1 Ultra"].allSatisfy { chip in
                let result = samples(chip, m1Fixture)
                return result.contains { $0.group == "CPU" } && result.contains { $0.group == "GPU" }
            }, "Select M1-family mappings for chip-name variants")
            try expect(Set(samples("Apple M1", ["TB0T": 28.1, "TB1T": 28.1]).map(\.group)) == ["Battery"], "Keep an M1 battery-only response out of CPU/GPU averages")
            try expect(!samples("Apple M10", m1Fixture).contains { $0.group == "CPU" || $0.group == "GPU" }, "Do not confuse M10 with M1")
            func machineForModel(_ model: String) -> MachineInfo {
                MachineInfo(chip: "Apple M1", model: model, cores: 8, performanceCores: 4, efficiencyCores: 4, memory: 8_589_934_592, os: "Test OS")
            }
            let air = machineForModel("MacBookAir10,1"), pro = machineForModel("MacBookPro17,1")
            try expect(air.displayName == "MacBook Air" && pro.displayName == "MacBook Pro", "Identify M1 Air and Pro by model rather than their shared chip name")
            try expect(air.isKnownFanless && !pro.isKnownFanless && !machineForModel("Unknown").isKnownFanless, "Only label the confirmed M1 Air model as fanless")
            try expect(machineForModel("Mac15,11").displayName == "MacBook Pro" && machineForModel("Unknown").displayName == "Mac", "Retain the tested M3 model label and avoid guessing unknown product families")
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
            let hidRows = [HIDTemperatureReading(name: "pACC MTR Temp Sensor0", value: 48),
                           HIDTemperatureReading(name: "eACC MTR Temp Sensor1", value: 42),
                           HIDTemperatureReading(name: "GPU MTR Temp Sensor0", value: 45),
                           HIDTemperatureReading(name: "SOC MTR Temp Sensor0", value: 80),
                           HIDTemperatureReading(name: "Battery", value: 28)]
            let hid = SensorCatalog.hidSamples(hidRows)
            try expect(hid.filter { $0.group == "CPU" }.map(\.value) == [48, 42], "Classify HID performance and efficiency thermal services as CPU")
            try expect(hid.filter { $0.group == "GPU" }.map(\.value) == [45], "Classify only GPU thermal services as GPU")
            try expect(hid.count == 3 && hid.allSatisfy { $0.source == "HID" }, "Keep SOC and battery readings out of HID CPU/GPU averages")
            try expect(SensorCatalog.hidSamples(hidRows + hidRows).count == 3, "Avoid double-counting duplicate HID product labels")
            let invalidHID = [HIDTemperatureReading(name: "pACC MTR Temp Sensor0", value: .nan),
                              HIDTemperatureReading(name: "eACC MTR Temp Sensor1", value: 0),
                              HIDTemperatureReading(name: "GPU MTR Temp Sensor0", value: 130),
                              HIDTemperatureReading(name: "GPU MTR Temp Sensor1", value: .infinity)]
            try expect(SensorCatalog.hidSamples(invalidHID).isEmpty, "Reject missing, zero, nonfinite and out-of-range HID temperatures")
            try expect(SensorCatalog.hidSamples([HIDTemperatureReading(name: "pACC MTR Temp Sensor", value: 40),
                                               HIDTemperatureReading(name: "GPU MTR Temp Sensor1 extra", value: 45)]).isEmpty, "Do not classify malformed or partial HID labels")
            let recovered = SensorCatalog.withHIDFallback(smc: batteryOnly, hid: hid)
            try expect(recovered.filter { $0.group == "CPU" }.count == 2 && recovered.filter { $0.group == "GPU" }.count == 1, "Fill both missing temperature groups through HID")
            try expect(recovered.contains { $0.id == "F0Ac" && $0.value == 0 }, "Preserve real zero RPM alongside HID fallback")
            let smcCPU = samples("Apple M1", ["Tp01": 50, "TB0T": 28])
            let partial = SensorCatalog.withHIDFallback(smc: smcCPU, hid: hid)
            try expect(partial.filter { $0.group == "CPU" }.map(\.id) == ["Tp01"] && partial.contains { $0.group == "GPU" && $0.source == "HID" }, "Fallback independently per group without mixing duplicate sensor interfaces")
            try expect(SensorCatalog.withHIDFallback(smc: m2, hid: hid).map(\.id) == m2.map(\.id), "Keep responding SMC CPU/GPU groups unchanged")
            try expect(!SensorCatalog.withHIDFallback(smc: batteryOnly, hid: []).contains { $0.group == "CPU" || $0.group == "GPU" }, "Leave temperatures unavailable when both interfaces have no valid readings")
            var diagnostic = SensorDiagnostics()
            diagnostic.hidStatus = "ok"
            diagnostic.hidProbes = [HIDProbeInfo(name: "pACC MTR Temp Sensor0", value: nil, status: "event-unavailable")]
            diagnostic.smcProbes = ["Tp01": SMCProbeInfo(status: "metadata-unavailable", dataType: "", byteCount: 0)]
            let diagnosticSnapshot = try SnapshotEncoder.encode(date: Date(timeIntervalSince1970: 0), machine: machine, cpu: CPUSample(), memory: memory, thermal: "Nominal", sensors: hid, processes: [], sensorDiagnostics: diagnostic)
            let diagnosticJSON = try JSONSerialization.jsonObject(with: diagnosticSnapshot) as! [String: Any]
            try expect((diagnosticJSON["sensorDiagnostics"] as? [String: Any])?["hidStatus"] as? String == "ok", "Include sensor-read diagnostics in exported snapshots")
            try expect((diagnosticJSON["sensors"] as? [[String: Any]])?.first?["source"] as? String == "HID", "Export which sensor interface supplied a temperature")
            try expect((decoded["sensors"] as? [[String: Any]])?.first?["source"] as? String == "SMC", "Retain explicit SMC attribution for existing sensors")
            let unavailableProbe = silicon_smc_probe(0, "Tp01")
            try expect(unavailableProbe.status == 1, "Report a missing SMC connection without a fabricated temperature")
            print("PASS: \(count) regression checks.")
            return 0
        } catch { fputs("FAIL: \(error)\n", stderr); return 1 }
    }
}
