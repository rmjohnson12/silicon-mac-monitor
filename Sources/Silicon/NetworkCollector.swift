import Foundation
import Darwin
import Network
import SystemConfiguration
import SensorBridge

struct NetworkCounter: Sendable {
    let name: String
    let index: UInt32
    let flags: UInt32
    let received: UInt64
    let sent: UInt64
    var linkActive: Bool? = nil
    var id: String { "\(name):\(index)" }
    var isActive: Bool { flags & UInt32(IFF_UP) != 0 && flags & UInt32(IFF_RUNNING) != 0 && flags & UInt32(IFF_LOOPBACK) == 0 && linkActive != false }
}

struct NetworkInterfaceSample: Identifiable, Sendable {
    let name: String
    let kind: String
    let addresses: [String]
    let active: Bool
    var id: String { name }
}

struct NetworkSample: Sendable {
    var downloadBytesPerSecond: Double?
    var uploadBytesPerSecond: Double?
    var receivedSessionBytes: UInt64 = 0
    var sentSessionBytes: UInt64 = 0
    var connection = "Detecting…"
    var routeStatus = "Checking connection"
    var routeAvailable = false
    var interfaces: [NetworkInterfaceSample] = []
    var readingsAvailable = true
    var addressesAvailable = true
    var segment = 0
    var activeInterfaceCount: Int { interfaces.filter(\.active).count }
    // Explicit allowlist: no addresses, adapter names, SSIDs or hardware IDs.
    var exportSummary: NetworkExport {
        NetworkExport(downloadBytesPerSecond: downloadBytesPerSecond, uploadBytesPerSecond: uploadBytesPerSecond,
                      receivedSessionBytes: receivedSessionBytes, sentSessionBytes: sentSessionBytes,
                      connection: connection, routeStatus: routeStatus, activeInterfaceCount: activeInterfaceCount,
                      readingsAvailable: readingsAvailable)
    }
}

struct NetworkExport: Codable, Sendable {
    let downloadBytesPerSecond: Double?
    let uploadBytesPerSecond: Double?
    let receivedSessionBytes: UInt64
    let sentSessionBytes: UInt64
    let connection: String
    let routeStatus: String
    let activeInterfaceCount: Int
    let readingsAvailable: Bool
}

struct NetworkPoint: Identifiable, Sendable {
    let id = UUID()
    let date: Date
    let downloadMbps: Double
    let uploadMbps: Double
    let segment: Int
}

// Counter math is independent of macOS so resets, hotplug and timing can be
// tested without generating internet traffic or changing network settings.
struct NetworkAccumulator {
    private var previous: [String: NetworkCounter] = [:]
    private var previousTime: Double?
    private(set) var received: UInt64 = 0
    private(set) var sent: UInt64 = 0
    private(set) var segment = 0
    mutating func resetBaseline() { previous = [:]; previousTime = nil; segment += 1 }
    mutating func update(_ counters: [NetworkCounter]?, time: Double) -> (Double?, Double?) {
        guard let counters, time.isFinite else { resetBaseline(); return (nil, nil) }
        let active = counters.filter(\.isActive)
        let current = Dictionary(active.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        defer { previous = current; previousTime = time }
        guard let before = previousTime, time > before, time - before <= 15 else {
            segment += 1; return (nil, nil)
        }
        var incoming: UInt64 = 0, outgoing: UInt64 = 0, comparable = 0
        var discontinuity = Set(previous.keys) != Set(current.keys)
        for (id, counter) in current {
            guard let old = previous[id] else { continue }
            guard counter.received >= old.received, counter.sent >= old.sent else { discontinuity = true; continue }
            incoming = Self.add(incoming, counter.received - old.received)
            outgoing = Self.add(outgoing, counter.sent - old.sent)
            comparable += 1
        }
        if discontinuity { segment += 1 }
        received = Self.add(received, incoming); sent = Self.add(sent, outgoing)
        guard comparable > 0 else { return (nil, nil) }
        return (Double(incoming) / (time - before), Double(outgoing) / (time - before))
    }
    private static func add(_ a: UInt64, _ b: UInt64) -> UInt64 {
        let sum = a.addingReportingOverflow(b)
        return sum.overflow ? UInt64.max : sum.partialValue
    }
}

final class NetworkCollector: @unchecked Sendable {
    private let monitor = NWPathMonitor()
    private let pathQueue = DispatchQueue(label: "local.silicon.network-path", qos: .utility)
    private let lock = NSLock()
    private var route = (available: false, status: "Checking connection", connection: "Detecting…")
    private var accumulator = NetworkAccumulator()

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            var kinds: [String] = []
            if path.usesInterfaceType(.wifi) { kinds.append("Wi-Fi") }
            if path.usesInterfaceType(.wiredEthernet) { kinds.append("Ethernet") }
            if path.usesInterfaceType(.cellular) { kinds.append("Cellular") }
            let available = path.status == .satisfied
            let state = (available: available, status: available ? "Route available" : "No network route",
                         connection: available ? (kinds.isEmpty ? "Other connection" : kinds.joined(separator: " + ")) : "Disconnected")
            guard let self else { return }
            self.lock.lock(); self.route = state; self.lock.unlock()
        }
        monitor.start(queue: pathQueue)
    }
    deinit { monitor.cancel() }
    // Sampling and baseline resets are serialized on MetricsStore's worker queue.
    func resetBaseline() { accumulator.resetBaseline() }

    func sample(time: Double = ProcessInfo.processInfo.systemUptime) -> NetworkSample {
        let physical = Self.physicalInterfaces()
        var counters: [NetworkCounter] = []
        let status = withUnsafeMutablePointer(to: &counters) { pointer in
            silicon_network_counters({ name, index, flags, linkActive, received, sent, context in
                guard let name, let context else { return }
                context.assumingMemoryBound(to: [NetworkCounter].self).pointee.append(
                    NetworkCounter(name: String(cString: name), index: index, flags: flags, received: received, sent: sent,
                                   linkActive: linkActive < 0 ? nil : linkActive == 1))
            }, UnsafeMutableRawPointer(pointer))
        }
        // Count physical hardware only. Including utun/bridge/awdl/loopback as
        // well as the underlying adapters would count the same traffic twice.
        let eligible = Self.hardwareCounters(counters, physical: physical ?? [:])
        let valid = status == 0 && physical != nil
        let rates = accumulator.update(valid ? eligible : nil, time: time)
        let addresses = Self.localAddresses()
        lock.lock(); let path = route; lock.unlock()
        var sample = NetworkSample(downloadBytesPerSecond: rates.0, uploadBytesPerSecond: rates.1,
                                   receivedSessionBytes: accumulator.received, sentSessionBytes: accumulator.sent,
                                   connection: path.connection, routeStatus: path.status, routeAvailable: path.available)
        sample.interfaces = eligible.map {
            NetworkInterfaceSample(name: $0.name, kind: physical?[$0.name] ?? "Adapter",
                                   addresses: addresses?[$0.name] ?? [], active: $0.isActive)
        }.sorted { $0.active != $1.active ? $0.active : $0.name < $1.name }
        sample.readingsAvailable = valid
        sample.addressesAvailable = addresses != nil
        sample.segment = accumulator.segment
        return sample
    }

    static func hardwareCounters(_ counters: [NetworkCounter], physical: [String: String]) -> [NetworkCounter] {
        counters.filter { physical[$0.name] != nil && $0.flags & UInt32(IFF_LOOPBACK) == 0 }
    }

    private static func physicalInterfaces() -> [String: String]? {
        guard let interfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] else { return nil }
        var result: [String: String] = [:]
        for interface in interfaces {
            guard let name = SCNetworkInterfaceGetBSDName(interface) as String?,
                  let type = SCNetworkInterfaceGetInterfaceType(interface) as String? else { continue }
            if type == (kSCNetworkInterfaceTypeIEEE80211 as String) { result[name] = "Wi-Fi" }
            else if type == (kSCNetworkInterfaceTypeEthernet as String) { result[name] = "Ethernet" }
            else if type == (kSCNetworkInterfaceTypeWWAN as String) { result[name] = "Cellular" }
        }
        return result
    }

    private static func localAddresses() -> [String: [String]]? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0 else { return nil }
        defer { if let head { freeifaddrs(head) } }
        var result: [String: [String]] = [:]
        var cursor = head
        while let node = cursor {
            let entry = node.pointee
            defer { cursor = entry.ifa_next }
            guard let address = entry.ifa_addr, let name = entry.ifa_name,
                  address.pointee.sa_family == AF_INET || address.pointee.sa_family == AF_INET6 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                let key = String(cString: name), value = String(cString: host)
                if !(result[key] ?? []).contains(value) { result[key, default: []].append(value) }
            }
        }
        return result.mapValues { $0.sorted() }
    }
}

extension Format {
    static func networkMbps(_ bytesPerSecond: Double?) -> String {
        guard let bytesPerSecond, bytesPerSecond.isFinite, bytesPerSecond >= 0 else { return "—" }
        let mbps = bytesPerSecond * 8 / 1_000_000
        return String(format: mbps >= 100 ? "%.0f" : "%.2f", mbps)
    }
    static func networkBytes(_ bytes: UInt64) -> String {
        // Network transfers use decimal units, unlike the app's RAM display.
        let value = Double(bytes)
        for (divisor, unit) in [(1e12, "TB"), (1e9, "GB"), (1e6, "MB"), (1e3, "KB")] {
            if value >= divisor { return String(format: "%.2f %@", value / divisor, unit) }
        }
        return "\(bytes) B"
    }
}
