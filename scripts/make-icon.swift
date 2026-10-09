import AppKit

// Reproducible, original artwork: two remaining-quota gauges on a macOS tile.
let destination = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "assets")
let iconset = destination.appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: alpha)
}

func rounded(_ rect: NSRect, radius: CGFloat, fill: NSColor) {
    fill.setFill()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
}

let canvas = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024,
                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                              isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
canvas.size = NSSize(width: 1024, height: 1024)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: canvas)
let tile = NSBezierPath(roundedRect: NSRect(x: 96, y: 96, width: 832, height: 832), xRadius: 184, yRadius: 184)
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = color(0x071224, alpha: 0.22)
shadow.shadowBlurRadius = 24
shadow.shadowOffset = NSSize(width: 0, height: -10)
shadow.set()
color(0x14243C).setFill()
tile.fill()
NSGraphicsContext.restoreGraphicsState()
NSGradient(starting: color(0x263B59), ending: color(0x101C31))!.draw(in: tile, angle: -90)

NSGraphicsContext.saveGraphicsState()
tile.addClip()
NSGradient(starting: color(0x33D7B2, alpha: 0.10), ending: color(0x33D7B2, alpha: 0))!
    .draw(in: NSBezierPath(ovalIn: NSRect(x: 70, y: 270, width: 610, height: 770)), relativeCenterPosition: NSPoint(x: 0, y: 0))
NSGraphicsContext.restoreGraphicsState()
color(0xFFFFFF, alpha: 0.13).setStroke()
tile.lineWidth = 3
tile.stroke()

for (x, amount, top, bottom) in [(CGFloat(292), CGFloat(365), UInt32(0x73F0CD), UInt32(0x1DBE99)),
                               (CGFloat(558), CGFloat(257), UInt32(0xA6B3FF), UInt32(0x677BF0))] {
    let rail = NSRect(x: x, y: 264, width: 174, height: 488)
    rounded(rail, radius: 63, fill: color(0xFFFFFF, alpha: 0.105))
    let fill = NSBezierPath(roundedRect: NSRect(x: x, y: 264, width: 174, height: amount), xRadius: 63, yRadius: 63)
    NSGradient(starting: color(top), ending: color(bottom))!.draw(in: fill, angle: -90)
    rounded(NSRect(x: x + 28, y: 792, width: 118, height: 17), radius: 8.5, fill: color(0xEDF4FF, alpha: 0.9))
    rounded(NSRect(x: x + 24, y: 294, width: 5, height: amount - 64), radius: 2.5, fill: color(0xFFFFFF, alpha: 0.13))
}
NSGraphicsContext.restoreGraphicsState()
try canvas.representation(using: .png, properties: [:])!.write(to: destination.appendingPathComponent("AppIcon.png"))

let master = NSImage(size: canvas.size)
master.addRepresentation(canvas)
for (name, pixels) in [("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
                       ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
                       ("icon_512x512", 512), ("icon_512x512@2x", 1024)] {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                 isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSGraphicsContext.current?.imageInterpolation = .high
    master.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent("\(name).png"))
}
print("Icon generated: \(destination.path)")
