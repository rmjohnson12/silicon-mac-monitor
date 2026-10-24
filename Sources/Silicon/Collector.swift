import Foundation
import Darwin
import SensorBridge

// All hardware collection is serialized on MetricsStore's worker queue.
final class Collector: @unchecked Sendable {
    private var previousCPU: [[UInt32]] = []
    private let connection = silicon_smc_open()
    private var availableSensors: [(key: String, name: String, group: String)]?
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
    private func read(_ key: String) -> Double? {
        var value = 0.0
        return key.withCString { silicon_smc_read(connection, $0, &value) } == 1 ? value : nil
    }
    func sensors() -> [SensorSample] {
        if availableSensors == nil {
            var candidates: [(String, String, String)] = []
            let chip = Collector.sysString("machdep.cpu.brand_string")
            if chip.contains("M3") {
                let efficiency = ["Te05", "Te0L", "Te0P", "Te0S"]
                let performance = ["Tf04", "Tf09", "Tf0A", "Tf0B", "Tf0D", "Tf0E", "Tf44", "Tf49", "Tf4A", "Tf4B", "Tf4D", "Tf4E"]
                let gpu = ["Tf14", "Tf18", "Tf19", "Tf1A", "Tf24", "Tf28", "Tf29", "Tf2A"]
                candidates += efficiency.enumerated().map { ($0.element, "Efficiency sensor \($0.offset + 1)", "CPU") }
                candidates += performance.enumerated().map { ($0.element, "Performance sensor \($0.offset + 1)", "CPU") }
                candidates += gpu.enumerated().map { ($0.element, "GPU sensor \($0.offset + 1)", "GPU") }
            } else {
                candidates += [("TC0P", "CPU proximity", "CPU"), ("TC0D", "CPU diode", "CPU"), ("TC0F", "CPU die", "CPU")]
            }
            candidates += [("TB0T", "Battery", "Battery"), ("TB1T", "Battery sensor 2", "Battery")]
            availableSensors = candidates.filter { if let v = read($0.0) { return v > 0 && v < 130 }; return false }
        }
        var samples = (availableSensors ?? []).compactMap { sensor -> SensorSample? in
            guard let value = read(sensor.key), value > 0, value < 130 else { return nil }
            return SensorSample(id: sensor.key, name: sensor.name, group: sensor.group, value: value)
        }
        for index in 0..<4 {
            let key = "F\(index)Ac"
            if let rpm = read(key), rpm >= 0, rpm < 15000 {
                samples.append(SensorSample(id: key, name: "Fan \(index + 1)", group: "Fan", value: rpm))
            }
        }
        return samples
    }
}
