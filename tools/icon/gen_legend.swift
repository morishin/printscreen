import AppKit
import CoreText

// 使い方: swift gen_legend.swift <Inter.ttf> <出力 legend.svg>
let args = CommandLine.arguments
let descriptors = CTFontManagerCreateFontDescriptorsFromURL(URL(fileURLWithPath: args[1]) as CFURL) as! [CTFontDescriptor]
let wght: UInt32 = 0x77676874, opsz: UInt32 = 0x6F70737A

func makeFont(_ size: CGFloat) -> CTFont {
    let variation: [NSNumber: NSNumber] = [NSNumber(value: wght): 500, NSNumber(value: opsz): 28]
    let descriptor = CTFontDescriptorCreateCopyWithAttributes(descriptors[0], [kCTFontVariationAttribute: variation] as CFDictionary)
    return CTFontCreateWithFontDescriptor(descriptor, size, nil)
}

func textPath(_ text: String, size: CGFloat, centerX: CGFloat, baseline: CGFloat) -> String {
    let font = makeFont(size)
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font]))
    let originX = centerX - CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)) / 2
    var d = ""
    func f(_ v: CGFloat) -> String { String(format: "%.2f", v) }
    for run in CTLineGetGlyphRuns(line) as! [CTRun] {
        let runFont = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName] as! CTFont
        let count = CTRunGetGlyphCount(run)
        var glyphs = [CGGlyph](repeating: 0, count: count)
        var positions = [CGPoint](repeating: .zero, count: count)
        CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
        CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
        for i in 0..<count {
            guard let path = CTFontCreatePathForGlyph(runFont, glyphs[i], nil) else { continue }
            let dx = originX + positions[i].x
            func x(_ p: CGPoint) -> String { f(p.x + dx) }
            func y(_ p: CGPoint) -> String { f(baseline - p.y) }
            path.applyWithBlock { element in
                let e = element.pointee
                switch e.type {
                case .moveToPoint: d += "M\(x(e.points[0])) \(y(e.points[0]))"
                case .addLineToPoint: d += "L\(x(e.points[0])) \(y(e.points[0]))"
                case .addQuadCurveToPoint: d += "Q\(x(e.points[0])) \(y(e.points[0])) \(x(e.points[1])) \(y(e.points[1]))"
                case .addCurveToPoint: d += "C\(x(e.points[0])) \(y(e.points[0])) \(x(e.points[1])) \(y(e.points[1])) \(x(e.points[2])) \(y(e.points[2]))"
                case .closeSubpath: d += "Z"
                @unknown default: break
                }
            }
        }
    }
    return d
}

// A 案と同じ配置
let (size, cx, first, sub): (CGFloat, CGFloat, CGFloat, CGFloat) = (116, 512, 340, 666)
let printPath = textPath("Print", size: size, centerX: cx, baseline: first)
let screenPath = textPath("Screen", size: size, centerX: cx, baseline: first + size * 1.18)
let sysrqPath = textPath("Sys Rq", size: size * 0.62, centerX: cx, baseline: sub)
let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"1024\" height=\"1024\" viewBox=\"100 100 824 824\"><path fill=\"#3B3933\" d=\"\(printPath)\"/><path fill=\"#3B3933\" d=\"\(screenPath)\"/><path fill=\"#4F8A3C\" d=\"\(sysrqPath)\"/></svg>"
try! svg.write(toFile: args[2], atomically: true, encoding: .utf8)
print("ok", CTFontCopyFullName(makeFont(size)), svg.count)
