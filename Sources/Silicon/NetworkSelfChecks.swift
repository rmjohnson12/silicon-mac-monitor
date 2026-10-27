import Foundation
import Darwin

enum NetworkSelfChecks {
    private struct Failure: Error, CustomStringConvertible { let description: String }
    static func run() throws -> Int {
        var count = 0
        func expect(_ condition: @autoclosure () -> Bool, _ description: String) throws {
            guard condition() else { throw Failure(description: description) }; count += 1
        }
        func counter(_ received: UInt64, _ sent: UInt64, name: String = "en0", index: UInt32 = 1, flags: UInt32 = UInt32(IFF_UP | IFF_RUNNING)) -> NetworkCounter {
            NetworkCounter(name: name, index: index, flags: flags, received: received, sent: sent)
        }
        var accumulator = NetworkAccumulator()
        let initial = accumulator.update([counter(5_000_000_000, 8_000_000_000)], time: 10)
        try expect(initial.0 == nil && initial.1 == nil && accumulator.received == 0, "Do not interpret since-boot counters as session traffic")
        let rate = accumulator.update([counter(5_001_000_000, 8_000_500_000)], time: 12)
        try expect(rate.0 == 500_000 && rate.1 == 250_000, "Use 64-bit counter deltas divided by actual elapsed seconds")
        try expect(accumulator.received == 1_000_000 && accumulator.sent == 500_000, "Accumulate observed byte deltas into session totals")
        let idle = accumulator.update([counter(5_001_000_000, 8_000_500_000)], time: 13)
        try expect(idle.0 == 0 && idle.1 == 0, "Distinguish idle zero traffic from unavailable readings")
        let reset = accumulator.update([counter(10, 20)], time: 14)
        try expect(reset.0 == nil && accumulator.received == 1_000_000, "A reset counter cannot underflow or inflate totals")
        let recovered = accumulator.update([counter(110, 70)], time: 15)
        try expect(recovered.0 == 100 && recovered.1 == 50, "Resume measurement after a counter reset establishes its new baseline")
        let segment = accumulator.segment
        accumulator.resetBaseline()
        let resumed = accumulator.update([counter(10_000, 20_000)], time: 20)
        try expect(resumed.0 == nil && accumulator.received == 1_000_100 && accumulator.segment > segment, "Exclude paused intervals and break chart segments while retaining totals")
        let gap = accumulator.update([counter(50_000, 60_000)], time: 40)
        try expect(gap.0 == nil && accumulator.received == 1_000_100, "Exclude long sampling gaps instead of showing a wake spike")
        _ = accumulator.update(nil, time: 41)
        let afterFailure = accumulator.update([counter(80_000, 90_000)], time: 42)
        try expect(afterFailure.0 == nil && accumulator.received == 1_000_100, "A failed read discards the baseline but preserves session totals")
        let noElapsed = accumulator.update([counter(80_100, 90_100)], time: 42)
        try expect(noElapsed.0 == nil, "Do not divide by zero on an equal timestamp")
        try expect(accumulator.update([counter(80_200, 90_200)], time: .nan).0 == nil, "Reject invalid sampling timestamps")

        var hotplug = NetworkAccumulator()
        _ = hotplug.update([counter(1_000, 1_000)], time: 1)
        let added = hotplug.update([counter(1_100, 1_050), counter(9_000_000, 8_000_000, name: "en5", index: 5)], time: 2)
        try expect(added.0 == 100 && hotplug.received == 100, "Newly attached adapters begin at a baseline without since-boot spikes")
        let aggregate = hotplug.update([counter(1_200, 1_100), counter(9_000_200, 8_000_100, name: "en5", index: 5)], time: 3)
        try expect(aggregate.0 == 300 && aggregate.1 == 150, "Sum deltas across multiple hardware adapters")
        let removed = hotplug.update([counter(9_000_250, 8_000_110, name: "en5", index: 5)], time: 4)
        try expect(removed.0 == 50 && hotplug.received == 450, "Adapter removal cannot subtract previously transferred data")
        let reused = hotplug.update([counter(1_000_000, 1_000_000, name: "en5", index: 6)], time: 5)
        try expect(reused.0 == nil && hotplug.received == 450, "A reused adapter name with a new interface index establishes a new baseline")

        let tunnel = counter(500, 500, name: "utun0", index: 10)
        let loopback = counter(500, 500, name: "lo0", index: 11, flags: UInt32(IFF_UP | IFF_RUNNING | IFF_LOOPBACK))
        let selected = NetworkCollector.hardwareCounters([counter(100, 50), tunnel, loopback], physical: ["en0": "Wi-Fi", "lo0": "Ethernet"])
        try expect(selected.map(\.name) == ["en0"], "Exclude tunnel and loopback counters to avoid counting traffic twice")
        var inactive = NetworkAccumulator()
        _ = inactive.update([counter(100, 100, flags: UInt32(IFF_UP))], time: 1)
        try expect(inactive.update([counter(500, 500, flags: UInt32(IFF_UP))], time: 2).0 == nil && inactive.received == 0, "Ignore adapters without a running link")
        var unplugged = counter(500, 500)
        unplugged.linkActive = false
        try expect(!unplugged.isActive, "An unplugged port is inactive even when the kernel running flag is set")
        try expect(Format.networkMbps(500_000) == "4.00" && Format.networkMbps(nil) == "—", "Convert bytes per second into decimal Mbps and preserve unavailable states")
        try expect(Format.networkBytes(1_000_000) == "1.00 MB", "Use decimal network transfer units")

        var sample = NetworkSample(downloadBytesPerSecond: 500_000, uploadBytesPerSecond: 250_000,
                                   receivedSessionBytes: 1_000_000, sentSessionBytes: 500_000, connection: "Wi-Fi", routeStatus: "Route available", routeAvailable: true)
        sample.interfaces = [NetworkInterfaceSample(name: "private-adapter-name", kind: "Wi-Fi", addresses: ["192.0.2.9", "2001:db8::9"], active: true)]
        let machine = MachineInfo(chip: "Test", model: "Test", cores: 8, performanceCores: 4, efficiencyCores: 4, memory: 1024, os: "Test")
        let exported = try SnapshotEncoder.encode(date: Date(timeIntervalSince1970: 0), machine: machine, cpu: CPUSample(), memory: MemorySample(), thermal: "Nominal", sensors: [], processes: [], network: sample)
        let text = String(decoding: exported, as: UTF8.self)
        let json = try JSONSerialization.jsonObject(with: exported) as! [String: Any]
        let network = json["network"] as? [String: Any]
        try expect(network?["downloadBytesPerSecond"] as? Double == 500_000 && network?["receivedSessionBytes"] as? Int == 1_000_000, "Export numeric aggregate throughput and session totals")
        try expect(!text.contains("192.0.2.9") && !text.contains("2001:db8::9") && !text.contains("private-adapter-name"), "Exclude local IPs and adapter identifiers from snapshots")
        try expect(network?["activeInterfaceCount"] as? Int == 1 && network?["connection"] as? String == "Wi-Fi", "Retain generic connection context without network identity")
        return count
    }
}
