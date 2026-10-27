import SwiftUI
import Charts
import AppKit

struct NetworkView: View {
    @ObservedObject var store: MetricsStore
    @Binding var range: Double
    @ViewState private var showInactive = false
    private var sample: NetworkSample { store.network }
    private var points: [NetworkPoint] { store.networkHistory(seconds: range) }
    private var end: Date { store.lastUpdate ?? Date() }
    private var ceiling: Double { max(1, (points.map { max($0.downloadMbps, $0.uploadMbps) }.max() ?? 0) * 1.15) }

    var body: some View {
        HStack(spacing: 16) {
            speedCard(title: "Download", icon: "arrow.down", rate: sample.downloadBytesPerSecond, total: sample.receivedSessionBytes, color: Palette.mint)
            speedCard(title: "Upload", icon: "arrow.up", rate: sample.uploadBytesPerSecond, total: sample.sentSessionBytes, color: Palette.blue)
            Card {
                VStack(alignment: .leading, spacing: 15) {
                    IconTile(icon: sample.connection.contains("Wi-Fi") ? "wifi" : "network", size: 32)
                    Text(sample.connection).font(.system(size: 20, weight: .medium)).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) {
                        Circle().fill(sample.routeAvailable ? Palette.mint : Palette.muted).frame(width: 5, height: 5)
                        Text(sample.routeStatus).font(.system(size: 10)).foregroundStyle(Palette.secondary)
                    }
                    Text("\(sample.activeInterfaceCount) active hardware adapter\(sample.activeInterfaceCount == 1 ? "" : "s")")
                        .font(.system(size: 9)).foregroundStyle(Palette.muted)
                }.frame(maxWidth: .infinity, alignment: .leading).frame(minHeight: 145)
            }.frame(width: 225)
        }
        Card {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("Traffic, in motion.").font(.system(size: 14, weight: .semibold))
                    Spacer()
                    DotLegend(text: "Download", color: Palette.mint)
                    DotLegend(text: "Upload", color: Palette.blue)
                }
                Chart(points) { point in
                    LineMark(x: .value("Time", point.date), y: .value("Mbps", point.downloadMbps),
                             series: .value("Series", "download-\(point.segment)"))
                        .foregroundStyle(Palette.mint).lineStyle(StrokeStyle(lineWidth: 2)).interpolationMethod(.linear)
                    LineMark(x: .value("Time", point.date), y: .value("Mbps", point.uploadMbps),
                             series: .value("Series", "upload-\(point.segment)"))
                        .foregroundStyle(Palette.blue).lineStyle(StrokeStyle(lineWidth: 2)).interpolationMethod(.linear)
                }
                .chartXScale(domain: end.addingTimeInterval(-range)...end)
                .chartYScale(domain: 0...ceiling)
                .chartXAxis {
                    AxisMarks(values: [end.addingTimeInterval(-range), end.addingTimeInterval(-range / 2), end]) { value in
                        AxisValueLabel { if let date = value.as(Date.self) { Text(date, format: .dateTime.hour().minute().second()).font(.system(size: 9, design: .monospaced)).foregroundStyle(Palette.muted) } }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 4])).foregroundStyle(Palette.border)
                        AxisValueLabel { if let rate = value.as(Double.self) { Text(String(format: rate >= 10 ? "%.0f" : "%.2f", rate)).font(.system(size: 9, design: .monospaced)).foregroundStyle(Palette.muted) } }
                    }
                }
                .frame(height: 180)
                .overlay { if points.isEmpty { Text("Collecting live traffic samples…").font(.system(size: 11)).foregroundStyle(Palette.secondary) } }
                .accessibilityLabel("Download and upload history in megabits per second, last \(Int(range / 60)) minutes")
                HStack {
                    Text("Mbps · current adapter traffic").font(.system(size: 10)).foregroundStyle(Palette.secondary)
                    Spacer()
                    Text("Includes local network activity").font(.system(size: 10)).foregroundStyle(Palette.muted)
                }
            }
        }
        HStack(alignment: .top, spacing: 16) {
            Card {
                VStack(alignment: .leading, spacing: 18) {
                    Eyebrow(text: "This session")
                    transferLine("Downloaded", bytes: sample.receivedSessionBytes, icon: "arrow.down", color: Palette.mint)
                    transferLine("Uploaded", bytes: sample.sentSessionBytes, icon: "arrow.up", color: Palette.blue)
                    Divider().overlay(Palette.border)
                    Text("Observed since Silicon opened. Paused intervals and gaps longer than 15 seconds are excluded.")
                        .font(.system(size: 10)).foregroundStyle(Palette.secondary).lineSpacing(4)
                    Text("Live traffic measures what your Mac is transferring. It isn’t your Wi-Fi link speed or an internet speed test.")
                        .font(.system(size: 10)).foregroundStyle(Palette.muted).lineSpacing(4)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(width: 260)
            Card {
                VStack(alignment: .leading, spacing: 16) {
                    HStack { Text("Connection details").font(.system(size: 14, weight: .semibold)); Spacer(); Image(systemName: "lock.shield").foregroundStyle(Palette.mint) }
                    if !sample.readingsAvailable {
                        Text("Adapter readings are unavailable. Silicon will try again on the next refresh.").font(.system(size: 11)).foregroundStyle(Palette.secondary)
                    } else if sample.activeInterfaceCount == 0 {
                        Text("No active hardware adapters.").font(.system(size: 11)).foregroundStyle(Palette.secondary)
                    }
                    ForEach(sample.interfaces.filter { $0.active || showInactive }) { interface in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                Image(systemName: interface.kind == "Wi-Fi" ? "wifi" : "network").foregroundStyle(Palette.secondary)
                                Text(interface.kind).fontWeight(.medium)
                                Text(interface.name).font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.muted)
                                Spacer()
                                Text(interface.active ? "Active" : "Inactive").font(.system(size: 9)).foregroundStyle(interface.active ? Palette.mint : Palette.muted)
                            }.font(.system(size: 11))
                            ForEach(interface.addresses, id: \.self) { address in
                                HStack(alignment: .top, spacing: 10) {
                                    Text(address.contains(":") ? "IPv6" : "IPv4").font(.system(size: 9)).foregroundStyle(Palette.muted).frame(width: 28, alignment: .leading)
                                    Text(address).font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.secondary).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                                    Spacer(minLength: 0)
                                    Button {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(address, forType: .string)
                                    } label: { Image(systemName: "doc.on.doc").font(.system(size: 10)) }
                                    .buttonStyle(.plain).foregroundStyle(Palette.muted).help("Copy \(address.contains(":") ? "IPv6" : "IPv4") address").accessibilityLabel("Copy \(interface.name) \(address.contains(":") ? "IPv6" : "IPv4") address")
                                }
                            }
                            if interface.addresses.isEmpty {
                                Text(sample.addressesAvailable ? "No IP address assigned" : "IP addresses unavailable").font(.system(size: 10)).foregroundStyle(Palette.muted)
                            }
                        }.padding(13).background(Palette.background.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
                    }
                    if sample.interfaces.contains(where: { !$0.active }) {
                        Button(showInactive ? "Hide inactive adapters" : "Show inactive adapters (\(sample.interfaces.filter { !$0.active }.count))") { showInactive.toggle() }
                            .buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(Palette.secondary)
                    }
                    Text("IP addresses stay in this view and are excluded from snapshots. No public-IP lookup or speed-test traffic is sent.")
                        .font(.system(size: 10)).foregroundStyle(Palette.muted).lineSpacing(4)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func speedCard(title: String, icon: String, rate: Double?, total: UInt64, color: Color) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 17) {
                HStack(spacing: 9) { IconTile(icon: icon, color: color, size: 30); Text(title).font(.system(size: 12, weight: .semibold)); Spacer() }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(Format.networkMbps(rate)).font(.system(size: 39, weight: .medium, design: .rounded)).tracking(-1).foregroundStyle(color).minimumScaleFactor(0.6).lineLimit(1)
                    Text("Mbps").font(.system(size: 11)).foregroundStyle(Palette.secondary)
                }
                Text(rate == nil ? (sample.readingsAvailable ? "Waiting for two comparable samples" : "Traffic readings unavailable") : "Current transfer rate")
                    .font(.system(size: 9)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
                Text("\(Format.networkBytes(total)) this session").font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.muted)
            }.frame(maxWidth: .infinity, alignment: .leading).frame(minHeight: 145)
        }
    }

    private func transferLine(_ title: String, bytes: UInt64, icon: String, color: Color) -> some View {
        HStack(spacing: 11) {
            IconTile(icon: icon, color: color, size: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 10)).foregroundStyle(Palette.secondary)
                Text(Format.networkBytes(bytes)).font(.system(size: 21, weight: .medium, design: .rounded)).foregroundStyle(color)
            }
        }
    }
}
