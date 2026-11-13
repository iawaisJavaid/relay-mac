import AppKit

let size = 1024
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                              samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                              bytesPerRow: 0, bitsPerPixel: 0)!
let context = NSGraphicsContext(bitmapImageRep: bitmap)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
context.imageInterpolation = .high

let outer = NSBezierPath(roundedRect: NSRect(x: 72, y: 72, width: 880, height: 880), xRadius: 202, yRadius: 202)
let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.17)
shadow.shadowBlurRadius = 32; shadow.shadowOffset = NSSize(width: 0, height: -14)
shadow.set()
NSColor(calibratedRed: 0.43, green: 0.30, blue: 0.81, alpha: 1).setFill(); outer.fill()
NSShadow().set()
NSGradient(starting: NSColor(calibratedRed: 0.58, green: 0.43, blue: 0.94, alpha: 1),
           ending: NSColor(calibratedRed: 0.33, green: 0.23, blue: 0.67, alpha: 1))!.draw(in: outer, angle: -65)

NSColor.white.withAlphaComponent(0.13).setStroke()
let ring = NSBezierPath(ovalIn: NSRect(x: 300, y: 260, width: 720, height: 720)); ring.lineWidth = 2; ring.stroke()

let display = NSBezierPath(roundedRect: NSRect(x: 233, y: 317, width: 510, height: 370), xRadius: 43, yRadius: 43)
NSColor.white.withAlphaComponent(0.98).setStroke(); display.lineWidth = 31; display.stroke()
let stem = NSBezierPath(); stem.move(to: NSPoint(x: 488, y: 316)); stem.line(to: NSPoint(x: 488, y: 243))
stem.lineWidth = 27; stem.lineCapStyle = .round; stem.stroke()
let base = NSBezierPath(); base.move(to: NSPoint(x: 377, y: 241)); base.line(to: NSPoint(x: 600, y: 241))
base.lineWidth = 27; base.lineCapStyle = .round; base.stroke()

let phoneRect = NSRect(x: 574, y: 265, width: 209, height: 395)
let phone = NSBezierPath(roundedRect: phoneRect, xRadius: 42, yRadius: 42)
NSColor(calibratedRed: 0.46, green: 0.32, blue: 0.82, alpha: 1).setFill(); phone.fill()
NSColor.white.setStroke(); phone.lineWidth = 25; phone.stroke()
let speaker = NSBezierPath(); speaker.move(to: NSPoint(x: 649, y: 623)); speaker.line(to: NSPoint(x: 708, y: 623))
speaker.lineWidth = 12; speaker.lineCapStyle = .round; speaker.stroke()
let home = NSBezierPath(); home.move(to: NSPoint(x: 650, y: 302)); home.line(to: NSPoint(x: 707, y: 302))
home.lineWidth = 9; home.lineCapStyle = .round; home.stroke()

NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
