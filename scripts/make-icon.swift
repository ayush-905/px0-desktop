import AppKit

// Draws the 1024-pixel app icon: "px0" in the system monospaced font on a
// dark rounded square, with px0's amber on the 0.
// Usage: make-icon <out.png>

let size = 1024
let output = CommandLine.arguments.dropFirst().first ?? "icon.png"
guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { exit(1) }
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

// The macOS icon grid: an 824-point body centred on the canvas.
let body = NSRect(x: 100, y: 100, width: 824, height: 824)
let shape = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)

NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
shadow.shadowBlurRadius = 24
shadow.shadowOffset = NSSize(width: 0, height: -10)
shadow.set()
NSColor.black.setFill()
shape.fill()
NSGraphicsContext.restoreGraphicsState()

NSGradient(starting: NSColor(srgbRed: 0.19, green: 0.20, blue: 0.22, alpha: 1),
           ending: NSColor(srgbRed: 0.07, green: 0.075, blue: 0.09, alpha: 1))?.draw(in: shape, angle: -90)
NSColor.white.withAlphaComponent(0.08).setStroke()
let rim = NSBezierPath(roundedRect: body.insetBy(dx: 2, dy: 2), xRadius: 183, yRadius: 183)
rim.lineWidth = 4
rim.stroke()

let font = NSFont.monospacedSystemFont(ofSize: 290, weight: .bold)
let text = NSMutableAttributedString(string: "px", attributes: [
    .font: font, .foregroundColor: NSColor(srgbRed: 0.93, green: 0.93, blue: 0.92, alpha: 1), .kern: -12,
])
text.append(NSAttributedString(string: "0", attributes: [
    .font: font, .foregroundColor: NSColor(srgbRed: 1.0, green: 0.53, blue: 0.0, alpha: 1),
]))
// Centre the band from the descender of "p" to the top of "0".
let width = text.size().width
let baseline = body.midY - (font.capHeight + font.descender) / 2
text.draw(at: NSPoint(x: body.midX - width / 2, y: baseline + font.descender))

NSGraphicsContext.restoreGraphicsState()
guard let png = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: URL(fileURLWithPath: output))
