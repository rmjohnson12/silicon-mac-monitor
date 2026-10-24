import SwiftUI
import AppKit

struct ProcessesView: View {
    @ObservedObject var store: MetricsStore
    @ViewState private var search = ""
    @ViewState private var scope = "All processes"
    @ViewState private var sortOrder = [KeyPathComparator(\ProcessSample.cpu, order: .reverse)]
    @ViewState private var selected: ProcessSample.ID?
    @FocusState private var searchFocused: Bool
    var filtered: [ProcessSample] {
        store.processes.filter { process in
            (search.isEmpty || process.name.localizedCaseInsensitiveContains(search) || String(process.id).contains(search)) && (scope != "Using CPU" || process.cpu >= 1)
        }.sorted(using: sortOrder)
    }
    private var selectedProcess: ProcessSample? { store.processes.first { $0.id == selected } }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    Eyebrow(text: "Process explorer")
                    Text("See what’s running.").font(.system(size: 29, weight: .medium)).tracking(-0.8)
                    Text("A closer look at the work behind your workflow.").font(.system(size: 11)).foregroundStyle(Palette.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 5) { Text("\(store.processes.count)").font(.system(size: 27, weight: .medium, design: .rounded)); Text("ACTIVE PROCESSES").font(.system(size: 8, design: .monospaced)).tracking(1).foregroundStyle(Palette.muted) }
            }.padding(.bottom, 7)
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Palette.muted)
                    TextField("Search by name or PID", text: $search).textFieldStyle(.plain).font(.system(size: 12)).focused($searchFocused).accessibilityLabel("Search processes")
                    if !search.isEmpty { Button { search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.muted) }.buttonStyle(.plain).accessibilityLabel("Clear search") }
                    if search.isEmpty { Text("⌘F").font(.system(size: 10)).foregroundStyle(Palette.muted) }
                }.padding(.horizontal, 12).frame(height: 36).background(Palette.card, in: RoundedRectangle(cornerRadius: 9)).overlay(RoundedRectangle(cornerRadius: 9).stroke(Palette.border))
                Picker("Filter", selection: $scope) { Text("All processes").tag("All processes"); Text("Using CPU (≥1%)").tag("Using CPU") }.labelsHidden().frame(width: 155)
                Button { store.openActivityMonitor() } label: { Label("Activity Monitor", systemImage: "arrow.up.right") }.buttonStyle(QuietButtonStyle())
            }
            VStack(spacing: 0) {
                Table(filtered, selection: $selected, sortOrder: $sortOrder) {
                    TableColumn("Process name", value: \.name) { process in
                        HStack(spacing: 10) { ProcessIcon(process: process, size: 25); Text(process.name).font(.system(size: 12)).lineLimit(1) }.padding(.vertical, 5)
                    }.width(min: 220, ideal: 350)
                    TableColumn("PID", value: \.id) { process in Text(String(process.id)).font(.system(size: 11, design: .monospaced)).foregroundStyle(Palette.muted) }.width(75)
                    TableColumn("CPU %", value: \.cpu) { process in
                        HStack { Spacer(); Text(Format.percent(process.cpu)).font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(process.cpu >= 1 ? Palette.mint : Palette.secondary) }
                    }.width(90)
                    TableColumn("Memory (RSS)", value: \.memory) { process in
                        HStack { Spacer(); Text(Format.memory(process.memory)).font(.system(size: 11, design: .monospaced)).foregroundStyle(Palette.secondary) }
                    }.width(120)
                }
                .scrollContentBackground(.hidden)
                .overlay {
                    if filtered.isEmpty {
                        VStack(spacing: 10) { Image(systemName: "magnifyingglass").font(.system(size: 26)).foregroundStyle(Palette.muted); Text(store.processes.isEmpty ? "Reading processes…" : "No matching processes").font(.system(size: 13)); Text("Try another name, PID, or filter.").font(.system(size: 11)).foregroundStyle(Palette.secondary) }.padding(30).background(Palette.card, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                Rectangle().fill(Palette.border).frame(height: 1)
                HStack { Text("\(filtered.count) of \(store.processes.count) processes"); Spacer(); Text("Select a process to inspect") }.font(.system(size: 10)).foregroundStyle(Palette.muted).padding(12)
            }.background(Palette.card, in: RoundedRectangle(cornerRadius: 12)).clipShape(RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.border))
            if let process = selectedProcess {
                Card(padding: 16) {
                    HStack(spacing: 14) {
                        ProcessIcon(process: process, size: 32)
                        VStack(alignment: .leading, spacing: 5) { Text(process.name).font(.system(size: 12, weight: .semibold)); Text(process.path).font(.system(size: 9, design: .monospaced)).foregroundStyle(Palette.muted).lineLimit(1).truncationMode(.middle).textSelection(.enabled) }
                        Spacer()
                        Text("\(Format.percent(process.cpu))% CPU  ·  \(Format.memory(process.memory))").font(.system(size: 11, design: .monospaced)).foregroundStyle(Palette.secondary)
                        Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: process.path)]) } label: { Image(systemName: "folder") }.buttonStyle(.plain).foregroundStyle(Palette.mint).help("Reveal executable in Finder").disabled(!FileManager.default.fileExists(atPath: process.path))
                    }
                }
            }
            HStack(alignment: .top, spacing: 7) {
                Image(systemName: "info.circle").padding(.top, 1)
                Text("Process CPU is the macOS ps decayed average: 100% equals one core and can exceed 100%. Memory is resident size; shared pages may appear in multiple processes.").lineSpacing(3)
            }.font(.system(size: 10)).foregroundStyle(Palette.muted)
        }.padding(28)
        .background { Button("Find Process") { searchFocused = true }.keyboardShortcut("f", modifiers: .command).hidden() }
        .onExitCommand { search = ""; searchFocused = false }
    }
}

@MainActor
private enum AppIconCache {
    static var icons: [String: NSImage] = [:]
    static func icon(for path: String) -> NSImage? {
        guard let appRange = path.range(of: ".app/") else { return nil }
        let bundle = String(path[..<appRange.lowerBound]) + ".app"
        if let image = icons[bundle] { return image }
        let image = NSWorkspace.shared.icon(forFile: bundle)
        if icons.count > 200 { icons.removeAll() }
        icons[bundle] = image
        return image
    }
}
struct ProcessIcon: View {
    let process: ProcessSample
    var size: CGFloat = 26
    var body: some View {
        Group {
            if let icon = AppIconCache.icon(for: process.path) { Image(nsImage: icon).resizable().interpolation(.high).scaledToFit() }
            else { Image(systemName: process.name.hasPrefix("kernel") ? "cpu" : "terminal").font(.system(size: size * 0.47)).foregroundStyle(Palette.secondary).frame(maxWidth: .infinity, maxHeight: .infinity).background(Palette.raised, in: RoundedRectangle(cornerRadius: 6)) }
        }.frame(width: size, height: size)
    }
}
