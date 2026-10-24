import AppKit

// Code-drawn public preview. These are illustrative sample values, never a
// screenshot of the developer's processes or a capture of live telemetry.
let destination = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "docs/assets/silicon-preview.png"
let size = NSSize(width: 1600, height: 1100)
let image = NSImage(size: size)
func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: alpha)
}
let ink = color(0x111413), card = color(0x1B201E), sidebar = color(0x151918)
let white = color(0xF0F3EF), secondary = color(0x9BA79F), muted = color(0x637168)
let mint = color(0xB4F3CA), blue = color(0x9ECBF5), lilac = color(0xC5B8EE), peach = color(0xF0C6A1)
func rounded(_ rect: NSRect, _ fill: NSColor, radius: CGFloat = 16, border: Bool = false) {
    let p = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    fill.setFill(); p.fill()
    if border { color(0xFFFFFF, 0.08).setStroke(); p.lineWidth = 1; p.stroke() }
}
func text(_ string: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat, _ c: NSColor = color(0xF0F3EF), _ weight: NSFont.Weight = .regular, mono: Bool = false) {
    let font = mono ? NSFont.monospacedSystemFont(ofSize: size, weight: weight) : NSFont.systemFont(ofSize: size, weight: weight)
    (string as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [.font: font, .foregroundColor: c])
}
func line(_ a: NSPoint, _ b: NSPoint, _ c: NSColor, width: CGFloat = 1) {
    let p = NSBezierPath(); p.move(to: a); p.line(to: b); p.lineWidth = width; c.setStroke(); p.stroke()
}
func symbol(_ name: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat, _ c: NSColor) {
    guard let original = NSImage(systemSymbolName: name, accessibilityDescription: nil),
          let icon = original.withSymbolConfiguration(.init(pointSize: size, weight: .regular)) else { return }
    let tinted = NSImage(size: icon.size)
    tinted.lockFocus(); icon.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
    c.setFill(); NSRect(origin: .zero, size: icon.size).fill(using: .sourceAtop); tinted.unlockFocus()
    tinted.draw(in: NSRect(x: x, y: y, width: size, height: size), from: .zero, operation: .sourceOver, fraction: 1)
}
func heading(_ title: String, _ icon: String, _ x: CGFloat, _ y: CGFloat, _ tint: NSColor) {
    rounded(NSRect(x: x, y: y - 3, width: 28, height: 28), tint.withAlphaComponent(0.09), radius: 8)
    symbol(icon, x + 7, y + 4, 14, tint)
    text(title, x + 40, y + 3, 13, white, .semibold)
}

image.lockFocus()
rounded(NSRect(origin: .zero, size: size), color(0xEDF2EE), radius: 0)
text("Silicon", 80, 1001, 46, ink, .semibold)
text("A closer look at your Mac.", 82, 962, 21, color(0x536358))
rounded(NSRect(x: 1274, y: 1000, width: 246, height: 36), color(0xDCE8DF), radius: 18)
text("NATIVE macOS  /  SWIFTUI", 1296, 1012, 12, color(0x40554A), .medium, mono: true)

NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.16); shadow.shadowBlurRadius = 40; shadow.shadowOffset = NSSize(width: 0, height: -12); shadow.set()
rounded(NSRect(x: 80, y: 190, width: 1440, height: 720), ink, radius: 24)
NSGraphicsContext.restoreGraphicsState()
NSGraphicsContext.saveGraphicsState()
NSBezierPath(roundedRect: NSRect(x: 80, y: 190, width: 1440, height: 720), xRadius: 24, yRadius: 24).addClip()
rounded(NSRect(x: 80, y: 190, width: 224, height: 720), sidebar, radius: 0)
line(NSPoint(x: 304, y: 190), NSPoint(x: 304, y: 910), color(0xFFFFFF, 0.07))
for (index, c) in [color(0xFF6058), color(0xFEBC2E), color(0x28C840)].enumerated() {
    c.setFill(); NSBezierPath(ovalIn: NSRect(x: 104 + index * 20, y: 880, width: 11, height: 11)).fill()
}
rounded(NSRect(x: 104, y: 811, width: 34, height: 34), mint, radius: 10)
symbol("waveform.path", 111, 818, 20, ink)
text("silicon", 148, 815, 24, white, .semibold)
text("WORKSPACE", 108, 766, 10, secondary, .medium, mono: true)
let nav = [("Overview", "square.grid.2x2"), ("CPU", "cpu"), ("Memory", "memorychip"), ("Thermals", "thermometer.medium"), ("Processes", "list.bullet.rectangle")]
for (index, item) in nav.enumerated() {
    let y = CGFloat(710 - index * 49)
    if index == 0 { rounded(NSRect(x: 96, y: y - 7, width: 192, height: 38), mint.withAlphaComponent(0.08), radius: 9) }
    symbol(item.1, 111, y + 3, 16, index == 0 ? mint : secondary)
    text(item.0, 140, y + 4, 13, index == 0 ? mint : secondary, index == 0 ? .semibold : .regular)
}
rounded(NSRect(x: 96, y: 252, width: 192, height: 164), ink, radius: 12, border: true)
symbol("laptopcomputer", 162, 340, 60, secondary)
text("MacBook Pro", 114, 310, 13, white, .semibold)
text("Apple M3 Max", 114, 288, 11, secondary)
text("On-device. Always.", 114, 268, 10, muted)
symbol("gearshape", 108, 215, 14, secondary); text("Preferences", 133, 216, 11, secondary)

text("My Mac   /   Overview", 332, 871, 12, secondary)
rounded(NSRect(x: 1410, y: 862, width: 80, height: 25), mint.withAlphaComponent(0.08), radius: 12)
text("●  LIVE", 1428, 870, 10, mint, .medium)
line(NSPoint(x: 304, y: 846), NSPoint(x: 1520, y: 846), color(0xFFFFFF, 0.07))
text("YOUR MAC, AT A GLANCE", 332, 815, 10, secondary, .medium, mono: true)
text("Everything, in balance.", 332, 774, 29, white, .semibold)
text("A live look at the little things powering your day.", 332, 751, 12, secondary)

for x: CGFloat in [332, 724, 1116] { rounded(NSRect(x: x, y: 520, width: 376, height: 214), card, radius: 18, border: true) }
heading("CPU", "cpu", 354, 691, mint); text("14 CORES", 619, 699, 9, muted, mono: true)
let center = NSPoint(x: 438, y: 603)
let track = NSBezierPath(ovalIn: NSRect(x: 386, y: 551, width: 104, height: 104)); track.lineWidth = 11; mint.withAlphaComponent(0.1).setStroke(); track.stroke()
let arc = NSBezierPath(); arc.appendArc(withCenter: center, radius: 52, startAngle: 90, endAngle: 3.6, clockwise: true); arc.lineWidth = 11; arc.lineCapStyle = .round; mint.setStroke(); arc.stroke()
text("24", 410, 595, 37, white, .medium); text("%", 458, 599, 16, secondary)
text("CPU usage", 410, 576, 10, secondary)
text("User", 535, 635, 10, muted); text("18.0%", 535, 615, 14, mint, .medium, mono: true)
text("System", 535, 590, 10, muted); text("6.0%", 535, 570, 14, blue, .medium, mono: true)
text("Idle  76.0%", 535, 543, 10, secondary, mono: true)
heading("Memory", "memorychip", 746, 691, lilac)
text("18.0", 746, 610, 40, white, .medium); text("/ 36 GB", 838, 617, 15, secondary)
rounded(NSRect(x: 746, y: 587, width: 332, height: 10), ink, radius: 4)
rounded(NSRect(x: 746, y: 587, width: 108, height: 10), lilac, radius: 3)
rounded(NSRect(x: 857, y: 587, width: 35, height: 10), blue, radius: 3)
rounded(NSRect(x: 895, y: 587, width: 17, height: 10), peach, radius: 3)
text("50.0% in use", 746, 564, 10, secondary); text("18.0 GB available", 976, 564, 10, secondary)
text("● App", 746, 540, 10, lilac); text("● Wired", 804, 540, 10, blue); text("● Compressed", 874, 540, 10, peach)
heading("Temperature", "thermometer.medium", 1138, 691, peach)
text("119°F", 1138, 609, 42, white, .medium); text("CPU sensor average", 1138, 585, 11, secondary)
line(NSPoint(x: 1138, y: 566), NSPoint(x: 1470, y: 566), color(0xFFFFFF, 0.07))
text("GPU", 1138, 540, 11, secondary); text("113°F", 1418, 538, 14, peach, .medium, mono: true)

rounded(NSRect(x: 332, y: 290, width: 756, height: 210), card, radius: 18, border: true)
text("CPU activity", 354, 469, 14, white, .semibold)
rounded(NSRect(x: 944, y: 460, width: 120, height: 29), ink, radius: 8); text("1m     5m     15m", 957, 470, 10, secondary)
for y: CGFloat in [345, 390, 435] { line(NSPoint(x: 354, y: y), NSPoint(x: 1064, y: y), color(0xFFFFFF, 0.055)) }
text("100%", 1027, 437, 9, muted, mono: true); text("50%", 1034, 392, 9, muted, mono: true)
let values: [CGFloat] = [20, 23, 32, 25, 22, 18, 26, 24, 38, 32, 29, 24, 20, 25, 22, 21, 29, 24, 28, 25, 23, 27, 24]
let graph = NSBezierPath(); let fill = NSBezierPath(); fill.move(to: NSPoint(x: 354, y: 345))
for (index, value) in values.enumerated() {
    let p = NSPoint(x: 354 + CGFloat(index) * 690 / CGFloat(values.count - 1), y: 345 + value * 1.4)
    if index == 0 { graph.move(to: p) } else { graph.line(to: p) }; fill.line(to: p)
}
fill.line(to: NSPoint(x: 1044, y: 345)); fill.close(); mint.withAlphaComponent(0.08).setFill(); fill.fill()
graph.lineWidth = 2; graph.lineJoinStyle = .round; mint.setStroke(); graph.stroke()
text("●  Total CPU", 354, 312, 10, mint); text("Last minute", 985, 312, 10, muted)
rounded(NSRect(x: 1104, y: 290, width: 388, height: 210), card, radius: 18, border: true)
text("Thermal health", 1126, 469, 14, white, .semibold); symbol("leaf", 1450, 469, 17, mint)
text("●  Nominal", 1126, 417, 28, mint, .medium)
text("Within normal thermal limits.", 1126, 387, 12, secondary)
line(NSPoint(x: 1126, y: 351), NSPoint(x: 1470, y: 351), color(0xFFFFFF, 0.07))
symbol("fan", 1126, 317, 17, muted); text("0 / 0 RPM", 1158, 320, 12, secondary, mono: true)
rounded(NSRect(x: 332, y: 214, width: 1160, height: 60), card, radius: 14, border: true)
symbol("list.bullet.rectangle", 354, 234, 20, mint); text("Process explorer", 388, 237, 13, white, .semibold)
text("Search by name or PID. Sort by CPU or memory. Inspect what’s running.", 558, 238, 12, secondary)
NSGraphicsContext.restoreGraphicsState()
text("SWIFTUI  ·  LIVE METRICS  ·  READ-ONLY SENSORS", 82, 122, 13, color(0x40554A), .medium, mono: true)
text("Illustrative interface preview · sample values", 82, 89, 15, color(0x6E7D73))
text("github.com/rmjohnson12/silicon-mac-monitor", 1110, 91, 12, color(0x536358))
image.unlockFocus()
let representation = NSBitmapImageRep(data: image.tiffRepresentation!)!
let url = URL(fileURLWithPath: destination)
try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
try representation.representation(using: .png, properties: [:])!.write(to: url)
print("Created: \(destination)")
