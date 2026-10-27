import SwiftUI
import AppKit

@MainActor
final class MetricsStore: ObservableObject {
    @Published var cpu = CPUSample()
    @Published var memory = MemorySample()
    @Published var processes: [ProcessSample] = []
    @Published var sensors: [SensorSample] = []
    @Published var network = NetworkSample()
    @Published var networkHistory: [NetworkPoint] = []
    private var sensorDiagnostics: SensorDiagnostics?
    @Published var history: [MetricPoint] = []
    @Published var thermal = ProcessInfo.processInfo.thermalState
    @Published var isPaused = false
    @Published var lastUpdate: Date?
    @Published var errors: [String] = []
    @Published var processUpdatedAt: Date?
    let machine = Collector.machine()
    private let queue = DispatchQueue(label: "local.silicon.metrics", qos: .utility)
    private let collector = Collector()
    private let networkCollector = NetworkCollector()
    private var timer: Timer?
    private var busy = false
    private var observer: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    var interval: Double { let value = UserDefaults.standard.double(forKey: "refreshInterval"); return [1.0, 2.0, 5.0].contains(value) ? value : 2 }
    var cpuTemperature: Double? { averageTemperature(group: "CPU") }
    var gpuTemperature: Double? { averageTemperature(group: "GPU") }
    var fans: [SensorSample] { sensors.filter { $0.group == "Fan" } }
    var thermalLabel: String {
        switch thermal { case .nominal: return "Nominal"; case .fair: return "Elevated"; case .serious: return "Serious"; case .critical: return "Critical"; @unknown default: return "Unknown" }
    }
    var thermalDescription: String {
        switch thermal {
        case .nominal: return "Your Mac is within normal thermal limits."
        case .fair: return "Your Mac is warming up. Keep its vents clear."
        case .serious: return "Thermal pressure is high. Consider pausing demanding work."
        case .critical: return "Thermal pressure is affecting performance. Give your Mac time to cool."
        @unknown default: return "The current thermal condition is unavailable."
        }
    }
    init() {
        startTimer()
        refresh()
        observer = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.startTimer() }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.resetBaselines() }
        }
    }
    private func averageTemperature(group: String) -> Double? {
        let values = sensors.filter { $0.group == group }.map(\.value)
        return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }
    private func startTimer() {
        if let timer, abs(timer.timeInterval - interval) < 0.01 { return }
        timer?.invalidate()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
    func togglePause() {
        isPaused.toggle()
        if !isPaused {
            // Discard the paused interval instead of presenting it as a live
            // CPU interval. Reset and sampling stay on the same serial queue.
            resetBaselines()
            refresh()
        }
    }
    private func resetBaselines() {
        queue.async { [collector, networkCollector] in collector.resetCPU(); networkCollector.resetBaseline() }
    }
    func refresh() {
        guard !busy, !isPaused else { return }
        busy = true
        let collector = collector
        let networkCollector = networkCollector
        queue.async { [weak self] in
            let cpu = collector.cpu()
            let memory = collector.memory()
            let sensors = collector.sensors()
            let sensorDiagnostics = collector.sensorDiagnostics
            let processes = Result { try collector.processes() }
            let network = networkCollector.sample()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.busy = false
                guard !self.isPaused else { return }
                var errors: [String] = []
                if let cpu { self.cpu = cpu }
                if let memory { self.memory = memory } else { errors.append("Memory readings are unavailable.") }
                self.sensors = sensors
                self.sensorDiagnostics = sensorDiagnostics
                self.network = network
                if let down = network.downloadBytesPerSecond, let up = network.uploadBytesPerSecond {
                    self.networkHistory.append(NetworkPoint(date: Date(), downloadMbps: down * 8 / 1_000_000, uploadMbps: up * 8 / 1_000_000, segment: network.segment))
                }
                self.networkHistory.removeAll { $0.date < Date().addingTimeInterval(-900) }
                switch processes {
                case .success(let list): self.processes = list; self.processUpdatedAt = Date()
                case .failure: errors.append("Process readings are unavailable. The previous list may be out of date.")
                }
                self.thermal = ProcessInfo.processInfo.thermalState
                self.errors = errors
                self.lastUpdate = Date()
                if let cpu, let memory {
                    self.history.append(MetricPoint(date: Date(), cpu: cpu.total, memory: memory.percent, temperature: self.cpuTemperature))
                    self.history.removeAll { $0.date < Date().addingTimeInterval(-900) }
                }
            }
        }
    }
    func history(seconds: Double) -> [MetricPoint] {
        let end = isPaused ? (lastUpdate ?? Date()) : Date()
        return history.filter { $0.date >= end.addingTimeInterval(-seconds) }
    }
    func networkHistory(seconds: Double) -> [NetworkPoint] {
        let end = isPaused ? (lastUpdate ?? Date()) : Date()
        return networkHistory.filter { $0.date >= end.addingTimeInterval(-seconds) }
    }
    func openActivityMonitor() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
    }
    func exportSnapshot() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Silicon-\(Date().formatted(.iso8601.year().month().day())) .json".replacingOccurrences(of: " .", with: ".")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try SnapshotEncoder.encode(date: lastUpdate ?? Date(), machine: machine, cpu: cpu, memory: memory, thermal: thermalLabel, sensors: sensors, processes: processes, sensorDiagnostics: sensorDiagnostics, network: network).write(to: url, options: .atomic)
        }
        catch { let alert = NSAlert(error: error); alert.runModal() }
    }
}
