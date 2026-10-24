import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: MetricsStore
    @AppStorage("refreshInterval") private var interval = 2.0
    @AppStorage("fahrenheit") private var fahrenheit = false
    @AppStorage("showMenuBar") private var showMenuBar = true
    var body: some View {
        VStack(alignment: .leading, spacing: 25) {
            HStack(spacing: 12) { IconTile(icon: "waveform.path", size: 44); VStack(alignment: .leading, spacing: 4) { Text("Make yourself at home.").font(.system(size: 21, weight: .medium)); Text("Silicon preferences").font(.system(size: 11)).foregroundStyle(Palette.secondary) } }
            Form {
                Picker("Refresh interval", selection: $interval) { Text("1 second").tag(1.0); Text("2 seconds").tag(2.0); Text("5 seconds").tag(5.0) }
                Toggle("Show CPU usage in the menu bar", isOn: $showMenuBar)
                Picker("Temperature readouts", selection: $fahrenheit) { Text("Celsius (°C)").tag(false); Text("Fahrenheit (°F)").tag(true) }
            }.formStyle(.grouped).scrollDisabled(true).frame(height: 170)
            HStack(alignment: .top, spacing: 10) { Image(systemName: "lock.shield").foregroundStyle(Palette.mint); Text("Your readings stay on this Mac. No account, analytics, or network connection. History covers the last 15 minutes of this session; snapshots are saved only when you export them.").font(.system(size: 11)).foregroundStyle(Palette.secondary).lineSpacing(4) }
            Text("SILICON 1.0  ·  \(store.machine.os)").font(.system(size: 9, design: .monospaced)).tracking(1).foregroundStyle(Palette.muted)
        }.padding(30).frame(width: 480).background(Palette.background).foregroundStyle(Palette.text).tint(Palette.mint)
    }
}

struct MenuPanel: View {
    @ObservedObject var store: MetricsStore
    @AppStorage("fahrenheit") private var fahrenheit = false
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack { Text("silicon").font(.system(size: 19, weight: .semibold, design: .rounded)); Spacer(); StatusBadge(text: store.isPaused ? "PAUSED" : "LIVE", color: store.isPaused ? Palette.peach : Palette.mint) }
            VStack(spacing: 8) {
                StatLine(label: "CPU", value: "\(Format.percent(store.cpu.total))%", color: Palette.mint)
                StatLine(label: "Memory", value: "\(Format.gb(store.memory.used)) / \(Int(store.memory.total / 1_073_741_824)) GB", color: Palette.lilac)
                StatLine(label: "CPU temperature", value: Format.temperature(store.cpuTemperature, fahrenheit: fahrenheit), color: Palette.peach)
                StatLine(label: "Thermal state", value: store.thermalLabel, color: Palette.thermal(store.thermal))
            }
            MetricChart(points: store.history(seconds: 60), seconds: 60, end: store.lastUpdate ?? Date(), showAxes: false).frame(height: 50)
            Button {
                if let window = NSApp.windows.first(where: { $0.title == "Silicon" && $0.isVisible }) {
                    window.makeKeyAndOrderFront(nil)
                } else { openWindow(id: "main") }
                NSApp.activate(ignoringOtherApps: true)
            } label: { HStack { Text("Open Silicon"); Spacer(); Image(systemName: "arrow.up.right") }.frame(maxWidth: .infinity) }.buttonStyle(QuietButtonStyle())
            HStack { Button(store.isPaused ? "Resume" : "Pause") { store.togglePause() }; Spacer(); Button("Preferences") { openSettings(); NSApp.activate(ignoringOtherApps: true) }; Button("Quit") { NSApp.terminate(nil) } }.buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(Palette.secondary)
        }.padding(20).frame(width: 290).background(Palette.background).foregroundStyle(Palette.text)
    }
}
