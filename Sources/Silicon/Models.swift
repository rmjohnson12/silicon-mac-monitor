import Foundation

struct ProcessSample: Identifiable, Sendable {
    let id: Int32
    let name: String
    let path: String
    let cpu: Double
    let memory: UInt64
}

struct SensorSample: Identifiable, Sendable {
    let id: String
    let name: String
    let group: String
    let value: Double
    var source: String { id.hasPrefix("HID:") ? "HID" : "SMC" }
}

struct SMCProbeInfo: Codable, Sendable {
    let status: String
    let dataType: String
    let byteCount: Int
}

struct SensorDiagnostics: Codable, Sendable {
    var smcConnectionOpen = false
    var smcProbes: [String: SMCProbeInfo] = [:]
    var hidStatus = "not-needed"
    var hidMatchedServices = 0
    var hidMissingEvents = 0
    var hidReturnedReadings = 0
    var hidRecognizedReadings = 0
    var hidProbes: [HIDProbeInfo] = []
    var missingTemperatureGroups: [String] = []
}

struct HIDProbeInfo: Codable, Sendable {
    let name: String
    let value: Double?
    let status: String
}

struct CPUSample: Sendable {
    var user: Double = 0
    var system: Double = 0
    var cores: [Double] = []
    var total: Double { user + system }
}

struct MemorySample: Sendable {
    var total: UInt64 = ProcessInfo.processInfo.physicalMemory
    var app: UInt64 = 0
    var wired: UInt64 = 0
    var compressed: UInt64 = 0
    var cached: UInt64 = 0
    var swap: UInt64 = 0
    var pressure: Int = 0
    var used: UInt64 { min(total, app + wired + compressed) }
    var available: UInt64 { total - used }
    var percent: Double { total > 0 ? Double(used) / Double(total) * 100 : 0 }
    var pressureLabel: String {
        switch pressure { case 1: return "Normal"; case 2: return "Elevated"; case 4: return "Critical"; default: return "Unavailable" }
    }
}

struct MachineInfo: Sendable {
    let chip: String
    let model: String
    let cores: Int
    let performanceCores: Int
    let efficiencyCores: Int
    let memory: UInt64
    let os: String

    var displayName: String {
        // Older identifiers include the product family; newer opaque ones
        // use only the models identified in our hardware reports so far.
        if model == "Mac15,11" || model == "Mac14,7" { return "MacBook Pro" }
        for (prefix, name) in [("MacBookAir", "MacBook Air"), ("MacBookPro", "MacBook Pro"),
                               ("MacBook", "MacBook"), ("Macmini", "Mac mini"),
                               ("MacStudio", "Mac Studio"), ("MacPro", "Mac Pro"), ("iMac", "iMac")] {
            if model.hasPrefix(prefix) { return name }
        }
        return "Mac"
    }

    // Confirmed fanless model. Missing RPM alone does not prove a Mac has no fan.
    var isKnownFanless: Bool { model == "MacBookAir10,1" }
    var fanUnavailableMessage: String { isKnownFanless ? "Fanless Mac · no fan installed" : "Fan readings unavailable" }
}

struct MetricPoint: Identifiable, Sendable {
    let id = UUID()
    let date: Date
    let cpu: Double
    let memory: Double
    let temperature: Double?
}

enum Format {
    static func gb(_ bytes: UInt64) -> String { String(format: "%.1f", Double(bytes) / 1_073_741_824) }
    static func memory(_ bytes: UInt64) -> String {
        bytes >= 1_073_741_824 ? "\(gb(bytes)) GB" : String(format: "%.0f MB", Double(bytes) / 1_048_576)
    }
    static func percent(_ value: Double) -> String { String(format: "%.1f", value) }
    static func uptime(_ seconds: TimeInterval) -> String {
        let days = Int(seconds) / 86400, hours = Int(seconds) / 3600 % 24, minutes = Int(seconds) / 60 % 60
        return days > 0 ? "\(days)d \(hours)h" : "\(hours)h \(minutes)m"
    }
    static func temperature(_ celsius: Double?, fahrenheit: Bool = false) -> String {
        guard let celsius else { return "—" }
        return String(format: "%.0f°%@", fahrenheit ? celsius * 1.8 + 32 : celsius, fahrenheit ? "F" : "C")
    }
}
