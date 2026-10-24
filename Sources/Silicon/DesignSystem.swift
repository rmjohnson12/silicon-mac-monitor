import SwiftUI
import Charts

// Use the established property-wrapper type explicitly. Recent SDKs also
// export a same-named State macro whose plugin isn't shipped with all CLTs.
typealias ViewState<Value> = SwiftUI.State<Value>

enum Palette {
    static let background = Color(hex: 0x111413)
    static let sidebar = Color(hex: 0x151918)
    static let card = Color(hex: 0x1B201E)
    static let raised = Color(hex: 0x252C28)
    static let border = Color.white.opacity(0.075)
    static let text = Color(hex: 0xF0F3EF)
    static let secondary = Color(hex: 0x9BA79F)
    static let muted = Color(hex: 0x637168)
    static let mint = Color(hex: 0xB4F3CA)
    static let blue = Color(hex: 0x9ECBF5)
    static let lilac = Color(hex: 0xC5B8EE)
    static let peach = Color(hex: 0xF0C6A1)
    static func thermal(_ state: ProcessInfo.ThermalState) -> Color {
        switch state { case .nominal: return mint; case .fair: return peach; case .serious, .critical: return .red; @unknown default: return secondary }
    }
    static func pressure(_ pressure: Int) -> Color {
        switch pressure { case 1: return mint; case 2: return peach; case 4: return .red; default: return secondary }
    }
}
extension Color {
    init(hex: UInt32) { self.init(.sRGB, red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, opacity: 1) }
}
struct Card<Content: View>: View {
    var padding: CGFloat = 22
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(padding).background(Palette.card, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Palette.border, lineWidth: 1))
    }
}
struct Eyebrow: View {
    let text: String
    var body: some View { Text(text.uppercased()).font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(1.6).foregroundStyle(Palette.secondary) }
}
struct StatusBadge: View {
    let text: String
    var color: Color = Palette.mint
    var body: some View {
        HStack(spacing: 6) { Circle().fill(color).frame(width: 5, height: 5); Text(text).font(.system(size: 10, weight: .medium)) }
            .foregroundStyle(color).padding(.horizontal, 9).padding(.vertical, 5).background(color.opacity(0.08), in: Capsule())
    }
}
struct IconTile: View {
    let icon: String
    var color = Palette.mint
    var size: CGFloat = 34
    var body: some View { Image(systemName: icon).font(.system(size: size * 0.43, weight: .medium)).foregroundStyle(color).frame(width: size, height: size).background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 10)) }
}
struct RingGauge: View {
    let value: Double
    var isReady = true
    var color = Palette.mint
    var label = "CPU usage"
    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.09), lineWidth: 12)
            Circle().trim(from: 0, to: max(0, min(value / 100, 1))).stroke(AngularGradient(colors: [color.opacity(0.4), color], center: .center, startAngle: .degrees(0), endAngle: .degrees(360)), style: StrokeStyle(lineWidth: 12, lineCap: .round)).rotationEffect(.degrees(-90))
            VStack(spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 1) { Text(isReady ? String(format: "%.0f", value) : "—").font(.system(size: 40, weight: .medium, design: .rounded)); if isReady { Text("%").font(.system(size: 18)).foregroundStyle(Palette.secondary) } }
                Text(label).font(.system(size: 10)).foregroundStyle(Palette.secondary)
            }
        }.padding(7).accessibilityElement(children: .ignore).accessibilityLabel(isReady ? "\(label), \(Int(value)) percent" : "\(label), collecting samples")
    }
}
struct MetricChart: View {
    let points: [MetricPoint]
    var metric = "cpu"
    var color = Palette.mint
    var seconds: Double = 60
    var end = Date()
    var showAxes = true
    private func value(_ point: MetricPoint) -> Double? {
        switch metric { case "memory": return point.memory; case "temperature": return point.temperature; default: return point.cpu }
    }
    var body: some View {
        Chart(points) { point in
            if let value = value(point) {
                AreaMark(x: .value("Time", point.date), yStart: .value("Baseline", 0), yEnd: .value("Usage", value))
                    .foregroundStyle(LinearGradient(colors: [color.opacity(0.22), color.opacity(0.01)], startPoint: .top, endPoint: .bottom)).interpolationMethod(.linear)
                LineMark(x: .value("Time", point.date), y: .value("Usage", value)).foregroundStyle(color).lineStyle(StrokeStyle(lineWidth: 1.8)).interpolationMethod(.linear)
                if points.count == 1 { PointMark(x: .value("Time", point.date), y: .value("Usage", value)).foregroundStyle(color).symbolSize(16) }
            }
        }
        .chartXScale(domain: end.addingTimeInterval(-seconds)...end)
        .chartYScale(domain: 0...(metric == "temperature" ? 120 : 100))
        .chartXAxis {
            if showAxes {
                AxisMarks(values: [end.addingTimeInterval(-seconds), end.addingTimeInterval(-seconds / 2), end]) { value in
                    AxisValueLabel { if let date = value.as(Date.self) { Text(date, format: .dateTime.hour().minute().second()).font(.system(size: 9, design: .monospaced)).foregroundStyle(Palette.muted) } }
                }
            }
        }
        .chartYAxis {
            if showAxes {
                AxisMarks(position: .trailing, values: [0, 50, 100]) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 4])).foregroundStyle(Palette.border)
                    AxisValueLabel { if let value = value.as(Int.self) { Text("\(value)\(metric == "temperature" ? "°" : "%")").font(.system(size: 9, design: .monospaced)).foregroundStyle(Palette.muted) } }
                }
            }
        }
        .accessibilityLabel("\(metric) history, last \(Int(seconds / 60)) minutes")
        .overlay { if points.isEmpty { Text("Collecting live samples…").font(.system(size: 11)).foregroundStyle(Palette.muted) } }
    }
}
struct StatLine: View {
    let label: String
    let value: String
    var color: Color = Palette.text
    var body: some View { HStack { Text(label).foregroundStyle(Palette.secondary); Spacer(); Text(value).foregroundStyle(color).monospacedDigit() }.font(.system(size: 11)).padding(.vertical, 4) }
}
struct DotLegend: View {
    let text: String
    let color: Color
    var body: some View { HStack(spacing: 6) { Circle().fill(color).frame(width: 5, height: 5); Text(text).font(.system(size: 10)).foregroundStyle(Palette.secondary) } }
}
struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.secondary)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Color.white.opacity(configuration.isPressed ? 0.1 : 0.04), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.border))
    }
}
