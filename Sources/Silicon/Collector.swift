import Foundation
import Darwin
import SensorBridge

// All hardware collection is serialized on MetricsStore's worker queue.
final class Collector: @unchecked Sendable {
    private var previousCPU: [[UInt32]] = []
    private let connection = silicon_smc_open()
    private let hidReader = HIDTemperatureReader()
    private(set) var sensorDiagnostics = SensorDiagnostics()
    private let temperatureDefinitions = SensorCatalog.temperatureDefinitions(chip: Collector.sysString("machdep.cpu.brand_string"))
    deinit { silicon_smc_close(connection) }
    func resetCPU() { previousCPU = [] }

    static func sysString(_ name: String) -> String {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return "Unknown" }
        var data = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &data, &size, nil, 0) == 0 else { return "Unknown" }
        return String(cString: data)
    }
    static func sysInt(_ name: String) -> Int {
        var number: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(name, &number, &size, nil, 0) == 0 else { return 0 }
        return Int(number)
    }
    static func machine() -> MachineInfo {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let chip = sysString("machdep.cpu.brand_string")
        return MachineInfo(chip: chip, model: sysString("hw.model"), cores: ProcessInfo.processInfo.processorCount,
                           performanceCores: sysInt("hw.perflevel0.physicalcpu"), efficiencyCores: sysInt("hw.perflevel1.physicalcpu"),
                           memory: ProcessInfo.processInfo.physicalMemory,
                           os: "macOS \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)")
    }
    func cpu() -> CPUSample? {
        var count: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        let status = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &count, &info, &infoCount)
        guard status == KERN_SUCCESS, let info else { return nil }
        defer { vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)), vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.size)) }
        var ticks: [[UInt32]] = []
        for core in 0..<Int(count) {
            ticks.append((0..<Int(CPU_STATE_MAX)).map { UInt32(bitPattern: info[core * Int(CPU_STATE_MAX) + $0]) })
        }
        defer { previousCPU = ticks }
        guard previousCPU.count == ticks.count else { return nil }
        var user = 0.0, system = 0.0, total = 0.0
        var cores: [Double] = []
        for (index, current) in ticks.enumerated() {
            let delta = zip(current, previousCPU[index]).map { Double($0 &- $1) }
            let sum = delta.reduce(0, +)
            let u = delta[Int(CPU_STATE_USER)] + delta[Int(CPU_STATE_NICE)]
            let s = delta[Int(CPU_STATE_SYSTEM)]
            cores.append(sum > 0 ? (u + s) / sum * 100 : 0)
            user += u; system += s; total += sum
        }
        guard total > 0 else { return nil }
        return CPUSample(user: user / total * 100, system: system / total * 100, cores: cores)
    }
    func memory() -> MemorySample? {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let page = UInt64(vm_kernel_page_size)
        // Anonymous pages include purgeable memory. Excluding it gives the
        // reclaimability-aware approximation used here for App Memory.
        let appPages = UInt64(stats.internal_page_count) > UInt64(stats.purgeable_count)
            ? UInt64(stats.internal_page_count) - UInt64(stats.purgeable_count) : 0
        var swap = xsw_usage(), size = MemoryLayout<xsw_usage>.size
        let swapStatus = sysctlbyname("vm.swapusage", &swap, &size, nil, 0)
        return MemorySample(app: appPages * page, wired: UInt64(stats.wire_count) * page,
                            compressed: UInt64(stats.compressor_page_count) * page,
                            cached: (UInt64(stats.external_page_count) + UInt64(stats.purgeable_count)) * page,
                            swap: swapStatus == 0 ? swap.xsu_used : 0,
                            pressure: Collector.sysInt("kern.memorystatus_vm_pressure_level"))
    }
    func processes() throws -> [ProcessSample] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-axo", "pid=,pcpu=,rss=,comm="]
        task.environment = ["LC_ALL": "C", "PATH": "/usr/bin:/bin"]
        let output = Pipe()
        task.standardOutput = output
        task.standardError = FileHandle.nullDevice
        try task.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard task.terminationStatus == 0, let text = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "Silicon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Process list could not be read."])
        }
        return Self.parseProcesses(text)
    }
    static func parseProcesses(_ text: String) -> [ProcessSample] {
        text.split(separator: "\n").compactMap { line in
            let fields = line.split(maxSplits: 3, omittingEmptySubsequences: true, whereSeparator: { $0.isWhitespace })
            guard fields.count == 4, let pid = Int32(fields[0]), let cpu = Double(fields[1]), let rss = UInt64(fields[2]), cpu.isFinite, cpu >= 0 else { return nil }
            let path = String(fields[3])
            return ProcessSample(id: pid, name: URL(fileURLWithPath: path).lastPathComponent, path: path, cpu: cpu, memory: rss * 1024)
        }
    }
    func sensors(forceHIDProbe: Bool = false) -> [SensorSample] {
        var diagnostics = SensorDiagnostics()
        diagnostics.smcConnectionOpen = connection != 0
        let labels = ["ok", "connection-unavailable", "invalid-key", "metadata-unavailable", "invalid-size", "read-failed", "unsupported-format", "nonfinite"]
        let smc = SensorCatalog.samples(definitions: temperatureDefinitions) { key in
            let probe = key.withCString { silicon_smc_probe(connection, $0) }
            let bytes = [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: probe.data_type >> $0) }
            let type = probe.data_type == 0 ? "" : String(bytes: bytes, encoding: .ascii) ?? "unknown"
            var status = labels.indices.contains(Int(probe.status)) ? labels[Int(probe.status)] : "unknown-error"
            if probe.status == 0 && (key.hasPrefix("F") ? !(0..<15000).contains(probe.value) : !(probe.value > 0 && probe.value < 130)) {
                status = "out-of-range"
            }
            diagnostics.smcProbes[key] = SMCProbeInfo(status: status, dataType: type, byteCount: Int(probe.data_size))
            return probe.status == 0 ? probe.value : nil
        }
        var result = smc
        if forceHIDProbe || !smc.contains(where: { $0.group == "CPU" }) || !smc.contains(where: { $0.group == "GPU" }) {
            let hid = hidReader.read()
            let recognized = SensorCatalog.hidSamples(hid.readings)
            diagnostics.hidStatus = hid.status
            diagnostics.hidMatchedServices = hid.matchedServices
            diagnostics.hidMissingEvents = hid.missingEvents
            diagnostics.hidReturnedReadings = hid.readings.filter { $0.value.isFinite }.count
            diagnostics.hidRecognizedReadings = recognized.count
            diagnostics.hidProbes = hid.readings.map {
                HIDProbeInfo(name: $0.name, value: $0.value.isFinite ? $0.value : nil,
                             status: !$0.value.isFinite ? "event-unavailable" : ($0.value > 0 && $0.value < 130 ? "ok" : "out-of-range"))
            }.sorted { $0.name < $1.name }
            result = SensorCatalog.withHIDFallback(smc: smc, hid: recognized)
        }
        diagnostics.missingTemperatureGroups = ["CPU", "GPU"].filter { group in !result.contains { $0.group == group } }
        sensorDiagnostics = diagnostics
        return result
    }
}
