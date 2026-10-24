import AppKit

let destination = CommandLine.arguments[1]
let size = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
let bounds = NSRect(x: 40, y: 40, width: 944, height: 944)
let shape = NSBezierPath(roundedRect: bounds, xRadius: 215, yRadius: 215)
NSGradient(starting: NSColor(srgbRed: 0.18, green: 0.24, blue: 0.20, alpha: 1), ending: NSColor(srgbRed: 0.065, green: 0.08, blue: 0.07, alpha: 1))!.draw(in: shape, angle: -70)
NSColor(white: 1, alpha: 0.13).setStroke()
shape.lineWidth = 2
shape.stroke()
let chip = NSBezierPath(roundedRect: NSRect(x: 252, y: 252, width: 520, height: 520), xRadius: 104, yRadius: 104)
NSColor(srgbRed: 0.70, green: 0.95, blue: 0.79, alpha: 0.08).setFill()
chip.fill()
NSColor(srgbRed: 0.70, green: 0.95, blue: 0.79, alpha: 0.35).setStroke()
chip.lineWidth = 9
chip.stroke()
for index in 0..<5 {
    let position = CGFloat(332 + index * 90)
    let pins = NSBezierPath()
    pins.move(to: NSPoint(x: position, y: 204)); pins.line(to: NSPoint(x: position, y: 239))
    pins.move(to: NSPoint(x: position, y: 785)); pins.line(to: NSPoint(x: position, y: 820))
    pins.move(to: NSPoint(x: 204, y: position)); pins.line(to: NSPoint(x: 239, y: position))
    pins.move(to: NSPoint(x: 785, y: position)); pins.line(to: NSPoint(x: 820, y: position))
    pins.lineWidth = 14; pins.lineCapStyle = .round; pins.stroke()
}
let wave = NSBezierPath()
let points: [(CGFloat, CGFloat)] = [(320, 504), (401, 504), (450, 625), (523, 385), (581, 566), (627, 504), (704, 504)]
wave.move(to: NSPoint(x: points[0].0, y: points[0].1))
for point in points.dropFirst() { wave.line(to: NSPoint(x: point.0, y: point.1)) }
wave.lineWidth = 25; wave.lineJoinStyle = .round; wave.lineCapStyle = .round
NSColor(srgbRed: 0.70, green: 0.95, blue: 0.79, alpha: 1).setStroke()
let glow = NSShadow(); glow.shadowColor = NSColor(srgbRed: 0.70, green: 0.95, blue: 0.79, alpha: 0.3); glow.shadowBlurRadius = 25; glow.set()
wave.stroke()
image.unlockFocus()
let representation = NSBitmapImageRep(data: image.tiffRepresentation!)!
try representation.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: destination))
