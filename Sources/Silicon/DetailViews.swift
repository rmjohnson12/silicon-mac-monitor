import SwiftUI

struct CPUDetailView: View {
    @ObservedObject var store: MetricsStore
    @Binding var range: Double
    var body: some View {
        HStack(spacing: 18) {
            Card {
                HStack(spacing: 27) {
                    RingGauge(value: store.cpu.total, isReady: !store.history.isEmpty).frame(width: 150, height: 150)
                    VStack(alignment: .leading, spacing: 10) {
                        Eyebrow(text: "Processor")
                        Text(store.machine.chip).font(.system(size: 22, weight: .medium))
                        Text("\(store.machine.performanceCores) performance + \(store.machine.efficiencyCores) efficiency cores").font(.system(size: 11)).foregroundStyle(Palette.secondary)
                        HStack(spacing: 20) { DotLegend(text: "User  \(Format.percent(store.cpu.user))%", color: Palette.mint); DotLegend(text: "System  \(Format.percent(store.cpu.system))%", color: Palette.blue) }.padding(.top, 9)
                    }
                    Spacer()
                }.frame(maxWidth: .infinity).frame(height: 170)
            }
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    Eyebrow(text: "Right now")
                    StatLine(label: "Idle", value: "\(Format.percent(100 - store.cpu.total))%")
                    StatLine(label: "Processes", value: "\(store.processes.count)")
                    StatLine(label: "System uptime", value: Format.uptime(ProcessInfo.processInfo.systemUptime))
                    StatLine(label: "Thermal state", value: store.thermalLabel, color: Palette.thermal(store.thermal))
                }.frame(height: 170)
            }.frame(width: 250)
        }
        Card {
            VStack(alignment: .leading, spacing: 22) {
                Text("CPU activity").font(.system(size: 14, weight: .semibold))
                MetricChart(points: store.history(seconds: range), seconds: range, end: store.lastUpdate ?? Date()).frame(height: 180)
            }
        }
        Card {
            VStack(alignment: .leading, spacing: 20) {
                HStack { Text("Every core").font(.system(size: 14, weight: .semibold)); Spacer(); Text("Instantaneous utilization").font(.system(size: 10)).foregroundStyle(Palette.muted) }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 7), spacing: 18) {
                    ForEach(Array(store.cpu.cores.enumerated()), id: \.offset) { index, value in
                        VStack(alignment: .leading, spacing: 9) {
                            HStack { Text("Core \(index + 1)").foregroundStyle(Palette.secondary); Spacer(); Text("\(Int(value))%").foregroundStyle(Palette.mint) }.font(.system(size: 10, design: .monospaced))
                            GeometryReader { geometry in ZStack(alignment: .leading) { Capsule().fill(Palette.background); Capsule().fill(Palette.mint).frame(width: geometry.size.width * min(1, max(0, value / 100))) } }.frame(height: 5)
                        }.padding(12).background(Palette.background.opacity(0.5), in: RoundedRectangle(cornerRadius: 9))
                    }
                }
                Text("Overall CPU is normalized across all \(store.machine.cores) logical cores. Per-process CPU uses a different scale.").font(.system(size: 10)).foregroundStyle(Palette.muted)
            }
        }
    }
}

struct MemoryDetailView: View {
    @ObservedObject var store: MetricsStore
    @Binding var range: Double
    var body: some View {
        HStack(spacing: 18) {
            Card {
                VStack(alignment: .leading, spacing: 23) {
                    HStack(alignment: .firstTextBaseline, spacing: 7) { Text(Format.gb(store.memory.used)).font(.system(size: 48, weight: .medium, design: .rounded)); Text("GB used of \(Int(store.memory.total / 1_073_741_824)) GB").font(.system(size: 14)).foregroundStyle(Palette.secondary); Spacer(); StatusBadge(text: store.memory.pressureLabel, color: Palette.pressure(store.memory.pressure)) }
                    MemoryBar(memory: store.memory).frame(height: 17)
                    HStack(spacing: 22) { DotLegend(text: "App memory", color: Palette.lilac); DotLegend(text: "Wired", color: Palette.blue); DotLegend(text: "Compressed", color: Palette.peach); DotLegend(text: "Available", color: Palette.muted) }
                }.frame(maxWidth: .infinity, alignment: .leading).frame(height: 150)
            }
            Card {
                VStack(alignment: .leading, spacing: 12) { Eyebrow(text: "Memory pressure"); Text(store.memory.pressureLabel).font(.system(size: 27, weight: .medium)).foregroundStyle(Palette.pressure(store.memory.pressure)); Text("Pressure comes from macOS and reflects more than the amount of RAM in use.").font(.system(size: 11)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true).lineSpacing(4) }.frame(height: 150)
            }.frame(width: 250)
        }
        Card {
            VStack(alignment: .leading, spacing: 22) { Text("Memory over time").font(.system(size: 14, weight: .semibold)); MetricChart(points: store.history(seconds: range), metric: "memory", color: Palette.lilac, seconds: range, end: store.lastUpdate ?? Date()).frame(height: 180) }
        }
        HStack(alignment: .top, spacing: 18) {
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    Text("The breakdown").font(.system(size: 14, weight: .semibold)).padding(.bottom, 5)
                    StatLine(label: "App memory (approx.)", value: Format.memory(store.memory.app), color: Palette.lilac)
                    StatLine(label: "Wired memory", value: Format.memory(store.memory.wired), color: Palette.blue)
                    StatLine(label: "Compressed", value: Format.memory(store.memory.compressed), color: Palette.peach)
                    StatLine(label: "Cached files", value: Format.memory(store.memory.cached))
                    StatLine(label: "Swap used", value: Format.memory(store.memory.swap))
                }.frame(maxWidth: .infinity)
            }
            Card {
                VStack(alignment: .leading, spacing: 16) {
                    HStack { Image(systemName: "sparkles").foregroundStyle(Palette.lilac); Text("Memory, made useful").font(.system(size: 14, weight: .semibold)) }
                    Text("macOS puts spare memory to work caching files. High usage alone doesn’t mean something is wrong; memory pressure is the better signal.").font(.system(size: 12)).foregroundStyle(Palette.secondary).lineSpacing(5)
                    Text("App memory is anonymous memory minus purgeable pages. Available memory includes reclaimable cache. Values may differ slightly from Activity Monitor.").font(.system(size: 10)).foregroundStyle(Palette.muted).lineSpacing(4)
                }.frame(maxWidth: .infinity, alignment: .leading).frame(minHeight: 210, alignment: .top)
            }
        }
    }
}

struct ThermalDetailView: View {
    @ObservedObject var store: MetricsStore
    @Binding var range: Double
    @AppStorage("fahrenheit") private var fahrenheit = false
    var body: some View {
        HStack(spacing: 18) {
            Card {
                VStack(alignment: .leading, spacing: 18) {
                    HStack { IconTile(icon: "leaf", color: Palette.thermal(store.thermal)); Spacer(); StatusBadge(text: "macOS thermal pressure", color: Palette.thermal(store.thermal)) }
                    Text(store.thermalLabel).font(.system(size: 34, weight: .medium)).foregroundStyle(Palette.thermal(store.thermal))
                    Text(store.thermalDescription).font(.system(size: 12)).foregroundStyle(Palette.secondary)
                    HStack(spacing: 5) {
                        ForEach(0..<4) { index in Capsule().fill(index <= store.thermal.rawValue ? Palette.thermal(store.thermal) : Palette.raised).frame(height: 5) }
                    }
                    HStack { Text("Nominal"); Spacer(); Text("Critical") }.font(.system(size: 9)).foregroundStyle(Palette.muted)
                }.frame(maxWidth: .infinity, alignment: .leading).frame(height: 210)
            }
            Card {
                VStack(alignment: .leading, spacing: 18) {
                    Eyebrow(text: "Temperature")
                    StatLine(label: "CPU average", value: Format.temperature(store.cpuTemperature, fahrenheit: fahrenheit), color: Palette.peach)
                    StatLine(label: "GPU average", value: Format.temperature(store.gpuTemperature, fahrenheit: fahrenheit), color: Palette.peach)
                    Divider().overlay(Palette.border)
                    ForEach(store.fans) { fan in HStack { Image(systemName: "fan").foregroundStyle(Palette.muted); StatLine(label: fan.name, value: "\(Int(fan.value)) RPM") } }
                    if store.fans.isEmpty { Text("Fan readings unavailable").font(.system(size: 11)).foregroundStyle(Palette.muted) }
                }.frame(maxWidth: .infinity, alignment: .leading).frame(height: 210)
            }.frame(width: 285)
        }
        Card {
            VStack(alignment: .leading, spacing: 20) {
                HStack { Text("CPU temperature").font(.system(size: 14, weight: .semibold)); Spacer(); Text("Average · °C").font(.system(size: 10)).foregroundStyle(Palette.muted) }
                MetricChart(points: store.history(seconds: range), metric: "temperature", color: Palette.peach, seconds: range, end: store.lastUpdate ?? Date()).frame(height: 170)
                    .overlay { if store.cpuTemperature == nil { Text("No CPU temperature sensor is available.").font(.system(size: 12)).foregroundStyle(Palette.secondary).padding(12).background(Palette.card) } }
                Text("Sensor temperatures and macOS thermal pressure measure different things. A warm chip can still have nominal thermal pressure.").font(.system(size: 10)).foregroundStyle(Palette.muted)
            }
        }
        Card {
            VStack(alignment: .leading, spacing: 18) {
                HStack { Text("Hardware sensors").font(.system(size: 14, weight: .semibold)); Spacer(); Text("\(store.sensors.filter { $0.group != "Fan" }.count) available").font(.system(size: 10)).foregroundStyle(Palette.muted) }
                if store.sensors.filter({ $0.group != "Fan" }).isEmpty {
                    Text("This Mac isn’t exposing temperature sensors to the app. macOS thermal pressure remains available above.").font(.system(size: 12)).foregroundStyle(Palette.secondary).padding(.vertical, 12)
                }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(store.sensors.filter { $0.group != "Fan" }) { sensor in
                        HStack { VStack(alignment: .leading, spacing: 5) { Text(sensor.name).font(.system(size: 10)); Text("\(sensor.group) · \(sensor.id)").font(.system(size: 9, design: .monospaced)).foregroundStyle(Palette.muted) }; Spacer(); Text(Format.temperature(sensor.value, fahrenheit: fahrenheit)).font(.system(size: 13, weight: .medium, design: .monospaced)).foregroundStyle(Palette.peach) }.padding(13).background(Palette.background.opacity(0.5), in: RoundedRectangle(cornerRadius: 9))
                    }
                }
                Text("Sensor names follow community M2/M3 mappings and may vary by hardware. Averages include only sensors that respond. Cooling remains managed by macOS.").font(.system(size: 10)).foregroundStyle(Palette.muted).lineSpacing(3)
            }
        }
    }
}
