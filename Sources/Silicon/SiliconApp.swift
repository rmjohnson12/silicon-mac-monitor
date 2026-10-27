import SwiftUI
import AppKit

@main
struct SiliconApp: App {
    @NSApplicationDelegateAdaptor(SiliconAppDelegate.self) private var appDelegate
    @StateObject private var store = MetricsStore()
    @AppStorage("showMenuBar") private var showMenuBar = true

    init() {
        if CommandLine.arguments.contains("--self-test") { exit(SelfChecks.run()) }
        if CommandLine.arguments.contains("--network-diagnostics") {
            let collector = NetworkCollector()
            _ = collector.sample()
            Thread.sleep(forTimeInterval: 1)
            let sample = collector.sample()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? encoder.encode(sample.exportSummary), let text = String(data: data, encoding: .utf8) { print(text) }
            exit(sample.readingsAvailable ? 0 : 1)
        }
        if CommandLine.arguments.contains("--sensor-diagnostics") {
            let collector = Collector()
            _ = collector.sensors(forceHIDProbe: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? encoder.encode(collector.sensorDiagnostics), let text = String(data: data, encoding: .utf8) { print(text) }
            exit(0)
        }
        if CommandLine.arguments.contains("--diagnostics") {
            Self.diagnostics()
            exit(0)
        }
    }
    var body: some Scene {
        WindowGroup("Silicon", id: "main") {
            ContentView(store: store)
                .preferredColorScheme(.dark)
                .frame(minWidth: 1080, minHeight: 740)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1240, height: 860)
        .commands {
            CommandGroup(after: .newItem) {
                Button(store.isPaused ? "Resume Monitoring" : "Pause Monitoring") { store.togglePause() }.keyboardShortcut("p", modifiers: [.command, .shift])
                Button("Export Snapshot…") { store.exportSnapshot() }.keyboardShortcut("e", modifiers: [.command, .shift])
            }
        }
        Settings { SettingsView(store: store).preferredColorScheme(.dark) }
        MenuBarExtra(isInserted: $showMenuBar) {
            MenuPanel(store: store).preferredColorScheme(.dark)
        } label: {
            Image(systemName: "waveform.path.ecg")
            Text(store.history.isEmpty ? "…" : "\(Int(store.cpu.total))%")
        }
        .menuBarExtraStyle(.window)
    }
    private static func diagnostics() {
        let collector = Collector()
        _ = collector.cpu()
        Thread.sleep(forTimeInterval: 1)
        let cpu = collector.cpu(), memory = collector.memory(), sensors = collector.sensors()
        let processes = (try? collector.processes()) ?? []
        let machine = Collector.machine()
        print("Silicon hardware diagnostics")
        print("\(machine.chip) | \(machine.cores) cores | \(Format.memory(machine.memory)) | \(machine.os)")
        print("CPU: \(cpu.map { Format.percent($0.total) } ?? "unavailable")% | Per-core readings: \(cpu?.cores.count ?? 0)")
        if let memory { print("Memory: \(Format.memory(memory.used)) / \(Format.memory(memory.total)); pressure: \(memory.pressureLabel); swap: \(Format.memory(memory.swap))") }
        print("Processes: \(processes.count)")
        for sensor in sensors { print("\(sensor.id) \(sensor.name): \(String(format: "%.1f", sensor.value)) \(sensor.group == "Fan" ? "RPM" : "°C")") }
        let valid = cpu.map { (0...100.001).contains($0.total) && $0.cores.count == machine.cores } ?? false
        let memoryValid = memory.map { $0.used > 0 && $0.used <= $0.total } ?? false
        if !valid || !memoryValid || processes.isEmpty { fputs("Diagnostics failed: missing or invalid live readings.\n", stderr); exit(1) }
        print("PASS: live CPU, memory and process readings are valid.")
    }
}

final class SiliconAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
