import SwiftUI

enum Destination: String, CaseIterable, Identifiable {
    case overview = "Overview", cpu = "CPU", memory = "Memory", thermals = "Thermals", processes = "Processes"
    var id: String { rawValue }
    var icon: String {
        switch self { case .overview: return "square.grid.2x2"; case .cpu: return "cpu"; case .memory: return "memorychip"; case .thermals: return "thermometer.medium"; case .processes: return "list.bullet.rectangle" }
    }
    var subtitle: String {
        switch self { case .overview: return "The bigger picture"; case .cpu: return "Every core, in focus"; case .memory: return "Room to do more"; case .thermals: return "Keep your cool"; case .processes: return "See what’s running" }
    }
}

struct ContentView: View {
    @ObservedObject var store: MetricsStore
    @ViewState private var destination: Destination = .overview
    @ViewState private var range = 60.0
    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 206)
            Rectangle().fill(Palette.border).frame(width: 1)
            VStack(spacing: 0) {
                header
                Rectangle().fill(Palette.border).frame(height: 1)
                if !store.errors.isEmpty {
                    HStack { Image(systemName: "exclamationmark.triangle"); Text(store.errors.joined(separator: " ")) }.font(.system(size: 11)).foregroundStyle(Palette.peach).padding(10)
                }
                if destination == .processes {
                    ProcessesView(store: store)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            introduction
                            switch destination {
                            case .overview: OverviewView(store: store, range: $range, destination: $destination)
                            case .cpu: CPUDetailView(store: store, range: $range)
                            case .memory: MemoryDetailView(store: store, range: $range)
                            case .thermals: ThermalDetailView(store: store, range: $range)
                            case .processes: EmptyView()
                            }
                            footer
                        }.padding(28)
                    }
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Palette.background)
        .foregroundStyle(Palette.text)
        .tint(Palette.mint)
        .background(WindowAppearance())
        .onReceive(NotificationCenter.default.publisher(for: .siliconNavigate)) { notification in
            if let target = notification.object as? Destination { destination = target }
        }
        .background {
            ForEach(Array(Destination.allCases.enumerated()), id: \.element) { index, target in
                Button(target.rawValue) { destination = target }.keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command).hidden()
            }
        }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                ZStack { RoundedRectangle(cornerRadius: 10).fill(Palette.mint).frame(width: 32, height: 32); Image(systemName: "waveform.path").font(.system(size: 19, weight: .semibold)).foregroundStyle(Palette.background) }
                Text("silicon").font(.system(size: 23, weight: .semibold, design: .rounded)).tracking(-0.8)
            }.padding(.horizontal, 24).padding(.top, 25).padding(.bottom, 39)
            Eyebrow(text: "Workspace").padding(.horizontal, 26).padding(.bottom, 12)
            VStack(spacing: 5) {
                ForEach(Destination.allCases) { target in
                    Button { destination = target } label: {
                        HStack(spacing: 11) {
                            Image(systemName: target.icon).font(.system(size: 14)).frame(width: 18)
                            Text(target.rawValue).font(.system(size: 12, weight: destination == target ? .semibold : .medium))
                            Spacer()
                            if destination == target { RoundedRectangle(cornerRadius: 2).fill(Palette.mint).frame(width: 3, height: 14) }
                        }.foregroundStyle(destination == target ? Palette.mint : Palette.secondary)
                            .padding(.horizontal, 13).frame(height: 40)
                            .background(destination == target ? Palette.mint.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 9))
                    }.buttonStyle(.plain).accessibilityIdentifier("nav-\(target.rawValue.lowercased())")
                }
            }.padding(.horizontal, 14)
            Spacer(minLength: 30)
            VStack(alignment: .leading, spacing: 13) {
                ZStack {
                    Ellipse().fill(Palette.mint.opacity(0.09)).frame(width: 100, height: 35).blur(radius: 15).offset(y: 12)
                    Image(systemName: "laptopcomputer").font(.system(size: 48, weight: .ultraLight)).foregroundStyle(Palette.secondary)
                }.frame(maxWidth: .infinity).frame(height: 66)
                VStack(alignment: .leading, spacing: 5) {
                    Text(store.machine.displayName).font(.system(size: 12, weight: .semibold))
                    Text(store.machine.chip).font(.system(size: 10)).foregroundStyle(Palette.secondary)
                    Text("\(Format.memory(store.machine.memory)) unified memory").font(.system(size: 10)).foregroundStyle(Palette.muted)
                }
                HStack { Image(systemName: "checkmark.shield"); Text("On-device. Always.") }.font(.system(size: 9)).foregroundStyle(Palette.muted)
            }.padding(16).background(Palette.background.opacity(0.55), in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.border)).padding(16)
            SettingsLink { HStack(spacing: 10) { Image(systemName: "gearshape"); Text("Preferences"); Spacer(); Text("⌘,").foregroundStyle(Palette.muted) }.font(.system(size: 11)).foregroundStyle(Palette.secondary).padding(.horizontal, 26).padding(.vertical, 14) }.buttonStyle(.plain)
            Rectangle().fill(Palette.border).frame(height: 1).padding(.top, 8)
            HStack(spacing: 7) { Circle().fill(store.isPaused ? Palette.peach : Palette.mint).frame(width: 5, height: 5); Text(store.isPaused ? "Monitoring paused" : "Monitoring your Mac").font(.system(size: 9)).foregroundStyle(Palette.secondary) }.padding(.horizontal, 24).frame(height: 42)
        }.background(Palette.sidebar)
    }
    private var header: some View {
        HStack {
            HStack(spacing: 9) {
                Image(systemName: "laptopcomputer").foregroundStyle(Palette.muted)
                Text("My Mac").foregroundStyle(Palette.secondary)
                Text("/").foregroundStyle(Palette.muted)
                Text(destination.rawValue).foregroundStyle(Palette.text)
            }.font(.system(size: 11))
            Spacer()
            StatusBadge(text: store.isPaused ? "PAUSED" : "LIVE", color: store.isPaused ? Palette.peach : Palette.mint)
            Text("Every \(Int(store.interval))s").font(.system(size: 10)).foregroundStyle(Palette.muted).padding(.leading, 4)
            Rectangle().fill(Palette.border).frame(width: 1, height: 17).padding(.horizontal, 10)
            Button { store.togglePause() } label: { Image(systemName: store.isPaused ? "play.fill" : "pause.fill").frame(width: 26, height: 28) }.buttonStyle(.plain).foregroundStyle(Palette.secondary).help(store.isPaused ? "Resume monitoring (⇧⌘P)" : "Pause monitoring (⇧⌘P)").accessibilityLabel(store.isPaused ? "Resume monitoring" : "Pause monitoring")
            Button { store.exportSnapshot() } label: { Image(systemName: "square.and.arrow.up").frame(width: 26, height: 28) }.buttonStyle(.plain).foregroundStyle(Palette.secondary).help("Export a local JSON snapshot").accessibilityLabel("Export snapshot")
        }.padding(.horizontal, 28).frame(height: 66)
    }
    private var introduction: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 8) {
                Eyebrow(text: destination == .overview ? "Your Mac, at a glance" : destination.rawValue + " monitor")
                Text(destination == .overview ? "Everything, in balance." : destination.subtitle).font(.system(size: 29, weight: .medium)).tracking(-0.8)
                Text(destination == .overview ? "A live look at the little things powering your day." : detailSubtitle).font(.system(size: 11)).foregroundStyle(Palette.secondary)
            }
            Spacer()
            if destination != .overview { RangePicker(range: $range) }
            else { Text(store.machine.os).font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.muted).padding(.top, 23) }
        }.padding(.bottom, 5)
    }
    private var detailSubtitle: String {
        switch destination {
        case .cpu: return "\(store.machine.cores) cores. One powerful piece of silicon."
        case .memory: return "\(Format.memory(store.machine.memory)) of unified memory, shared across your Mac."
        case .thermals: return "Live hardware sensors and thermal pressure, side by side."
        default: return ""
        }
    }
    private var footer: some View {
        HStack {
            Text("Made for a closer look.").font(.system(size: 10)).foregroundStyle(Palette.muted)
            Spacer()
            if let last = store.lastUpdate { Text("\(store.isPaused ? "Paused at" : "Updated") \(last.formatted(date: .omitted, time: .standard))").font(.system(size: 9, design: .monospaced)).foregroundStyle(Palette.muted) }
        }.padding(.top, 2)
    }
}
struct RangePicker: View {
    @Binding var range: Double
    var body: some View {
        HStack(spacing: 2) {
            ForEach([60.0, 300.0, 900.0], id: \.self) { value in
                Button { range = value } label: {
                    Text("\(Int(value / 60))m").font(.system(size: 10, weight: .medium)).foregroundStyle(range == value ? Palette.text : Palette.muted).frame(width: 35, height: 25).background(range == value ? Palette.raised : .clear, in: RoundedRectangle(cornerRadius: 6))
                }.buttonStyle(.plain).help("Show the last \(Int(value / 60)) minutes")
            }
        }.padding(3).background(Palette.background, in: RoundedRectangle(cornerRadius: 8))
    }
}
extension Notification.Name { static let siliconNavigate = Notification.Name("SiliconNavigate") }
struct WindowAppearance: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            view.window?.backgroundColor = NSColor(Palette.background)
            view.window?.titlebarAppearsTransparent = true
            view.window?.isMovableByWindowBackground = true
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
