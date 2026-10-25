import Foundation

struct TemperatureSensorDefinition: Sendable {
    let key: String
    let name: String
    let group: String
}

// Hardware identifiers checked against the community mappings cited in
// THIRD_PARTY_NOTICES.md. Sensor numbering does not imply one sensor per core.
enum SensorCatalog {
    static func temperatureDefinitions(chip: String) -> [TemperatureSensorDefinition] {
        let words = chip.split(whereSeparator: { $0.isWhitespace })
        let generation = words.first == "Apple" && words.count > 1 ? String(words[1]) : ""
        var result: [TemperatureSensorDefinition] = []
        func append(_ keys: [String], name: String, group: String) {
            result += keys.enumerated().map {
                TemperatureSensorDefinition(key: $0.element, name: "\(name) \($0.offset + 1)", group: group)
            }
        }
        switch generation {
        case "M2":
            append(["Tp1h", "Tp1t", "Tp1p", "Tp1l"], name: "Efficiency sensor", group: "CPU")
            append(["Tp01", "Tp05", "Tp09", "Tp0D", "Tp0X", "Tp0b", "Tp0f", "Tp0j"], name: "Performance sensor", group: "CPU")
            append(["Tg0f", "Tg0j"], name: "GPU sensor", group: "GPU")
        case "M3":
            append(["Te05", "Te0L", "Te0P", "Te0S"], name: "Efficiency sensor", group: "CPU")
            append(["Tf04", "Tf09", "Tf0A", "Tf0B", "Tf0D", "Tf0E", "Tf44", "Tf49", "Tf4A", "Tf4B", "Tf4D", "Tf4E"], name: "Performance sensor", group: "CPU")
            append(["Tf14", "Tf18", "Tf19", "Tf1A", "Tf24", "Tf28", "Tf29", "Tf2A"], name: "GPU sensor", group: "GPU")
        default:
            result += [
                TemperatureSensorDefinition(key: "TC0P", name: "CPU proximity", group: "CPU"),
                TemperatureSensorDefinition(key: "TC0D", name: "CPU diode", group: "CPU"),
                TemperatureSensorDefinition(key: "TC0F", name: "CPU diode (filtered)", group: "CPU")
            ]
        }
        result += [
            TemperatureSensorDefinition(key: "TB0T", name: "Battery", group: "Battery"),
            TemperatureSensorDefinition(key: "TB1T", name: "Battery sensor 2", group: "Battery")
        ]
        return result
    }

    static func samples(definitions: [TemperatureSensorDefinition], read: (String) -> Double?) -> [SensorSample] {
        // Re-probe on every interval. A sensor missing during startup or wake
        // can recover without permanently disappearing from the session.
        var samples = definitions.compactMap { sensor -> SensorSample? in
            guard let value = read(sensor.key), value.isFinite, value > 0, value < 130 else { return nil }
            return SensorSample(id: sensor.key, name: sensor.name, group: sensor.group, value: value)
        }
        for index in 0..<4 {
            let key = "F\(index)Ac"
            if let rpm = read(key), rpm.isFinite, rpm >= 0, rpm < 15000 {
                samples.append(SensorSample(id: key, name: "Fan \(index + 1)", group: "Fan", value: rpm))
            }
        }
        return samples
    }
}
