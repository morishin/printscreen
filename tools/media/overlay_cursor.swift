import AppKit

_ = NSApplication.shared

// 入力画像の波紋の中心（ピクセル、左上原点: 640, 352）に矢印カーソルの先端を合わせて描く
let args = CommandLine.arguments
let source = NSBitmapImageRep(data: try! Data(contentsOf: URL(fileURLWithPath: args[1])))!
let (w, h) = (source.pixelsWide, source.pixelsHigh)
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGraphicsContext.current?.imageInterpolation = .high
source.draw(in: NSRect(x: 0, y: 0, width: w, height: h))
let cursor = NSCursor.arrow
let scale: CGFloat = 2
let size = NSSize(width: cursor.image.size.width * scale, height: cursor.image.size.height * scale)
let tip = CGPoint(x: 640, y: CGFloat(h) - 352)
let rect = NSRect(x: tip.x - cursor.hotSpot.x * scale,
                  y: tip.y - size.height + cursor.hotSpot.y * scale,
                  width: size.width, height: size.height)
let tiff = cursor.image.tiffRepresentation!
let reps = NSBitmapImageRep.imageReps(with: tiff).compactMap { $0 as? NSBitmapImageRep }
let best = reps.max { $0.pixelsWide < $1.pixelsWide }!
print("cursor", cursor.image.size, cursor.hotSpot, reps.map { "\($0.pixelsWide)x\($0.pixelsHigh)" })
best.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: false, hints: [.interpolation: NSImageInterpolation.high.rawValue])
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
