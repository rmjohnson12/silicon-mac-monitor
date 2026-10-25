import Foundation
import SensorBridge

struct HIDTemperatureReading: Sendable {
    let name: String
    let value: Double
}

struct HIDTemperatureResult: Sendable {
    let readings: [HIDTemperatureReading]
    let status: String
    let matchedServices: Int
    let missingEvents: Int
}

// Owned by Collector and called only on its serial worker queue.
final class HIDTemperatureReader {
    private let reader = silicon_hid_create()
    deinit { silicon_hid_destroy(reader) }

    func read() -> HIDTemperatureResult {
        var readings: [HIDTemperatureReading] = []
        var matched: UInt32 = 0, missing: UInt32 = 0
        let status = withUnsafeMutablePointer(to: &readings) { pointer in
            silicon_hid_read(reader, { name, value, context in
                guard let name, let context else { return }
                context.assumingMemoryBound(to: [HIDTemperatureReading].self).pointee.append(
                    HIDTemperatureReading(name: String(cString: name), value: value))
            }, UnsafeMutableRawPointer(pointer), &matched, &missing)
        }
        let labels = ["ok", "api-unavailable", "client-unavailable", "services-unavailable"]
        return HIDTemperatureResult(readings: readings,
                                    status: labels.indices.contains(Int(status)) ? labels[Int(status)] : "unknown-error",
                                    matchedServices: Int(matched), missingEvents: Int(missing))
    }
}
