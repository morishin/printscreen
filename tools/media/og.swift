import AppKit
let a = CommandLine.arguments
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1200, pixelsHigh: 630, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSColor(srgbRed: 0.937, green: 0.918, blue: 0.867, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: 1200, height: 630).fill()
let shot = NSImage(contentsOfFile: a[1])!
let w: CGFloat = 800, h = w * shot.size.height / shot.size.width
shot.draw(in: NSRect(x: 420, y: (630 - h) / 2, width: w, height: h))
let icon = NSImage(contentsOfFile: a[2])!
icon.draw(in: NSRect(x: 56, y: 305, width: 190, height: 190))
NSAttributedString(string: "PrintScreen", attributes: [.font: NSFont.systemFont(ofSize: 54, weight: .bold), .foregroundColor: NSColor(srgbRed: 0.18, green: 0.17, blue: 0.157, alpha: 1)]).draw(at: CGPoint(x: 62, y: 230))
NSAttributedString(string: "Capture. Annotate. Save.", attributes: [.font: NSFont.systemFont(ofSize: 25, weight: .medium), .foregroundColor: NSColor(srgbRed: 0.4, green: 0.38, blue: 0.31, alpha: 1)]).draw(at: CGPoint(x: 64, y: 190))
NSGraphicsContext.current?.flushGraphics()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: a[3]))
