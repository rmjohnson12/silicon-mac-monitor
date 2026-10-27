import Foundation

enum SnapshotEncoder {
    static func encode(date: Date, machine: MachineInfo, cpu: CPUSample, memory: MemorySample, thermal: String, sensors: [SensorSample], processes: [ProcessSample], sensorDiagnostics: SensorDiagnostics? = nil, network: NetworkSample? = nil) throws -> Data {
        let sensorRows: [[String: Any]] = sensors.map { ["key": $0.id, "name": $0.name, "group": $0.group, "source": $0.source, "value": $0.value, "unit": $0.group == "Fan" ? "RPM" : "C"] }
        let rows: [[String: Any]] = processes.map { ["pid": $0.id, "name": $0.name, "cpuPercent": $0.cpu, "residentBytes": $0.memory] }
        var snapshot: [String: Any] = [
            "capturedAt": date.ISO8601Format(), "chip": machine.chip,
            "model": machine.model, "os": machine.os, "logicalCoreCount": machine.cores,
            "appVersion": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development",
            "cpuPercent": cpu.total, "memoryUsedBytes": memory.used, "memoryTotalBytes": memory.total,
            "memoryPressure": memory.pressureLabel, "swapUsedBytes": memory.swap,
            "thermalState": thermal, "sensors": sensorRows, "processes": rows,
            "notes": "Process CPU is ps interval-decayed usage, 100% per logical core. Memory is resident size, not private footprint. App Memory is an approximation."
        ]
        if let sensorDiagnostics {
            snapshot["sensorDiagnostics"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(sensorDiagnostics))
        }
        if let network { snapshot["network"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(network.exportSummary)) }
        return try JSONSerialization.data(withJSONObject: snapshot, options: [.prettyPrinted, .sortedKeys])
    }
}
