import SwiftUI

struct OverviewView: View {
    @ObservedObject var store: MetricsStore
    @Binding var range: Double
    @Binding var destination: Destination
    @AppStorage("fahrenheit") private var fahrenheit = false
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            cpuCard
            memoryCard
            temperatureCard
        }
        HStack(alignment: .top, spacing: 16) {
            activityCard.frame(maxWidth: .infinity)
            thermalCard.frame(width: 270)
        }
        Card(padding: 0) {
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Taking the lead").font(.system(size: 13, weight: .semibold))
                        Text("Processes using the most CPU right now").font(.system(size: 10)).foregroundStyle(Palette.secondary)
                    }
                    Spacer()
                    Button { destination = .processes } label: { HStack(spacing: 6) { Text("All processes"); Image(systemName: "arrow.up.right") }.font(.system(size: 10)).foregroundStyle(Palette.secondary) }.buttonStyle(.plain)
                }.padding(.horizontal, 20).padding(.vertical, 17)
                HStack { Text("PROCESS"); Spacer(); Text("CPU").frame(width: 75, alignment: .trailing); Text("MEMORY").frame(width: 95, alignment: .trailing) }.font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(1).foregroundStyle(Palette.muted).padding(.horizontal, 22).padding(.bottom, 9)
                ForEach(Array(store.processes.sorted { $0.cpu > $1.cpu }.prefix(4))) { process in
                    Rectangle().fill(Palette.border).frame(height: 1)
                    HStack(spacing: 10) {
                        ProcessIcon(process: process, size: 23)
                        Text(process.name).font(.system(size: 11, weight: .medium)).lineLimit(1)
                        Text("\(process.id)").font(.system(size: 9, design: .monospaced)).foregroundStyle(Palette.muted)
                        Spacer()
                        Text("\(Format.percent(process.cpu))%").foregroundStyle(Palette.mint).frame(width: 75, alignment: .trailing)
                        Text(Format.memory(process.memory)).foregroundStyle(Palette.secondary).frame(width: 95, alignment: .trailing)
                    }.font(.system(size: 10, design: .monospaced)).monospacedDigit().padding(.horizontal, 22).frame(height: 41)
                }
                if store.processes.isEmpty { Text("Reading running processes…").font(.system(size: 11)).foregroundStyle(Palette.secondary).padding(20) }
            }
        }
    }
    private var cpuCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 13) {
                HStack { IconTile(icon: "cpu", size: 28); Text("CPU").font(.system(size: 11, weight: .semibold)); Spacer(); Text("\(store.machine.cores) CORES").font(.system(size: 8, design: .monospaced)).foregroundStyle(Palette.muted) }
                HStack(spacing: 18) {
                    RingGauge(value: store.cpu.total, isReady: !store.history.isEmpty).frame(width: 116, height: 116)
                    VStack(alignment: .leading, spacing: 13) {
                        smallValue("User", "\(Format.percent(store.cpu.user))%", Palette.mint)
                        smallValue("System", "\(Format.percent(store.cpu.system))%", Palette.blue)
                        smallValue("Idle", "\(Format.percent(max(0, 100 - store.cpu.total)))%", Palette.secondary)
                    }
                }.frame(maxWidth: .infinity)
                Text(store.machine.chip).font(.system(size: 10)).foregroundStyle(Palette.muted)
            }.frame(maxWidth: .infinity, alignment: .leading).frame(height: 185)
        }
    }
    private var memoryCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 16) {
                HStack { IconTile(icon: "memorychip", color: Palette.lilac, size: 28); Text("Memory").font(.system(size: 11, weight: .semibold)); Spacer(); Image(systemName: "circle.lefthalf.filled").font(.system(size: 12)).foregroundStyle(Palette.lilac) }
                HStack(alignment: .firstTextBaseline, spacing: 4) { Text(Format.gb(store.memory.used)).font(.system(size: 37, weight: .medium, design: .rounded)).tracking(-1); Text("/ \(Int(store.memory.total / 1_073_741_824)) GB").font(.system(size: 13)).foregroundStyle(Palette.secondary) }
                MemoryBar(memory: store.memory).frame(height: 9)
                HStack { Text("\(Format.percent(store.memory.percent))% in use"); Spacer(); Text("\(Format.gb(store.memory.available)) GB available") }.font(.system(size: 9)).foregroundStyle(Palette.secondary)
                HStack(spacing: 12) { DotLegend(text: "App", color: Palette.lilac); DotLegend(text: "Wired", color: Palette.blue); DotLegend(text: "Compressed", color: Palette.peach) }
            }.frame(maxWidth: .infinity, alignment: .leading).frame(height: 185)
        }
    }
    private var temperatureCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 15) {
                HStack { IconTile(icon: "thermometer.medium", color: Palette.peach, size: 28); Text("Temperature").font(.system(size: 11, weight: .semibold)); Spacer() }
                Text(Format.temperature(store.cpuTemperature, fahrenheit: fahrenheit)).font(.system(size: 37, weight: .medium, design: .rounded)).tracking(-1)
                Text(store.cpuTemperature == nil ? "CPU sensor unavailable" : "CPU sensor average").font(.system(size: 10)).foregroundStyle(Palette.secondary)
                Rectangle().fill(Palette.border).frame(height: 1)
                HStack { Text("GPU").font(.system(size: 10)).foregroundStyle(Palette.secondary); Spacer(); Text(Format.temperature(store.gpuTemperature, fahrenheit: fahrenheit)).font(.system(size: 12, weight: .medium, design: .monospaced)).foregroundStyle(Palette.peach) }
            }.frame(maxWidth: .infinity, alignment: .leading).frame(height: 185)
        }
    }
    private var activityCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack { Text("CPU activity").font(.system(size: 13, weight: .semibold)); Spacer(); RangePicker(range: $range) }
                MetricChart(points: store.history(seconds: range), seconds: range, end: store.lastUpdate ?? Date()).frame(height: 111)
                HStack { DotLegend(text: "Total CPU", color: Palette.mint); Spacer(); Text("\(store.processes.count) processes").font(.system(size: 9, design: .monospaced)).foregroundStyle(Palette.muted) }
            }.frame(height: 185)
        }
    }
    private var thermalCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 13) {
                HStack { Text("Thermal health").font(.system(size: 13, weight: .semibold)); Spacer(); Image(systemName: "leaf").foregroundStyle(Palette.thermal(store.thermal)) }
                HStack(alignment: .firstTextBaseline, spacing: 7) { Circle().fill(Palette.thermal(store.thermal)).frame(width: 7, height: 7); Text(store.thermalLabel).font(.system(size: 23, weight: .medium)) }
                Text(store.thermalDescription).font(.system(size: 10)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true).lineSpacing(3)
                Spacer(minLength: 0)
                HStack {
                    Image(systemName: "fan").font(.system(size: 13)).foregroundStyle(Palette.muted)
                    Text(store.fans.isEmpty ? store.machine.fanUnavailableMessage : store.fans.map { "\(Int($0.value))" }.joined(separator: " / ") + " RPM").font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.secondary)
                    Spacer()
                    Button { destination = .thermals } label: { Image(systemName: "arrow.up.right").font(.system(size: 11)).foregroundStyle(Palette.muted) }.buttonStyle(.plain).help("View thermal sensors")
                }.padding(.top, 10).overlay(alignment: .top) { Rectangle().fill(Palette.border).frame(height: 1) }
            }.frame(height: 185)
        }
    }
    private func smallValue(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) { Text(label).font(.system(size: 9)).foregroundStyle(Palette.muted); Text(value).font(.system(size: 12, weight: .medium, design: .monospaced)).foregroundStyle(color) }
    }
}
struct MemoryBar: View {
    let memory: MemorySample
    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 2) {
                segment(memory.app, Palette.lilac, proxy.size.width)
                segment(memory.wired, Palette.blue, proxy.size.width)
                segment(memory.compressed, Palette.peach, proxy.size.width)
                Spacer(minLength: 0)
            }.frame(maxWidth: .infinity).background(Palette.background).clipShape(RoundedRectangle(cornerRadius: 4))
        }.accessibilityLabel("\(Int(memory.percent)) percent of memory used")
    }
    private func segment(_ bytes: UInt64, _ color: Color, _ width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 2).fill(color).frame(width: max(0, width * Double(bytes) / Double(max(1, memory.total)) - 2))
    }
}
