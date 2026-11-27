// Rounds the corners of a captured System Settings sheet, outlines its checkboxes in red,
// and scales it down for the Shortcuts settings tab.
// Usage: swift annotate_shortcuts.swift <in.png> <out.png> sheetX sheetY sheetW sheetH [x y w h]...
import AppKit

let args = CommandLine.arguments
let numbers = args.dropFirst(3).compactMap(Double.init)
guard args.count >= 7, numbers.count >= 8, numbers.count % 4 == 0,
      let source = NSImage(contentsOfFile: args[1])?.cgImage(forProposedRect: nil, context: nil, hints: nil)
else {
    FileHandle.standardError.write("usage: annotate_shortcuts.swift <in.png> <out.png> sheetX sheetY sheetW sheetH [x y w h]...\n".data(using: .utf8)!)
    exit(1)
}

let sheet = CGRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3])
let boxes = stride(from: 4, to: numbers.count, by: 4).map {
    CGRect(x: numbers[$0], y: numbers[$0 + 1], width: numbers[$0 + 2], height: numbers[$0 + 3])
}

/// Output width in pixels: 440 pt at 2x, the width of the image in the settings tab.
let outputWidth = 880
let scale = CGFloat(outputWidth) / sheet.width // pixels per point
let size = CGSize(width: outputWidth, height: Int((sheet.height * scale).rounded()))

let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.interpolationQuality = .high
let bounds = CGRect(origin: .zero, size: size)

// Cut off the desktop that shows through the sheet's corners
ctx.addPath(CGPath(roundedRect: bounds, cornerWidth: 26 * scale, cornerHeight: 26 * scale, transform: nil))
ctx.clip()
ctx.draw(source, in: bounds)
ctx.resetClip()

// Outline every checkbox. Accessibility frames are top-left origin; CGContext is bottom-left.
let union = boxes.dropFirst().reduce(boxes[0]) { $0.union($1) }
let local = CGRect(x: (union.minX - sheet.minX) * scale,
                   y: (sheet.maxY - union.maxY) * scale,
                   width: union.width * scale, height: union.height * scale)
    .insetBy(dx: -12 * scale, dy: -12 * scale)
let lineWidth = 3 * scale
ctx.setStrokeColor(NSColor.systemRed.usingColorSpace(.sRGB)!.cgColor)
ctx.setLineWidth(lineWidth)
ctx.addPath(CGPath(roundedRect: local.insetBy(dx: lineWidth / 2, dy: lineWidth / 2),
                   cornerWidth: 10 * scale, cornerHeight: 10 * scale, transform: nil))
ctx.strokePath()

let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
print("wrote \(args[2]) (\(Int(size.width))×\(Int(size.height)))")
