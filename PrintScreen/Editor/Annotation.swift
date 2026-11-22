import Accelerate
import AppKit

enum EditorTool: String, CaseIterable, Identifiable {
    case select, arrow, line, rect, ellipse, fill, text, pen, mosaic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .select: String(localized: "Select")
        case .arrow: String(localized: "Arrow")
        case .line: String(localized: "Line")
        case .rect: String(localized: "Rectangle")
        case .ellipse: String(localized: "Ellipse")
        case .fill: String(localized: "Fill")
        case .text: String(localized: "Text")
        case .pen: String(localized: "Pen")
        case .mosaic: String(localized: "Mosaic")
        }
    }

    var symbol: String {
        switch self {
        case .select: "cursorarrow"
        case .arrow: "arrow.up.right"
        case .line: "line.diagonal"
        case .rect: "rectangle"
        case .ellipse: "circle"
        case .fill: "rectangle.fill"
        case .text: "a.square" // textformat は中国語環境で別の字形になる
        case .pen: "scribble"
        case .mosaic: "checkerboard.rectangle"
        }
    }

    /// 1 文字のショートカット
    var key: String {
        switch self {
        case .select: "v"
        case .arrow: "a"
        case .line: "l"
        case .rect: "r"
        case .ellipse: "o"
        case .fill: "f"
        case .text: "t"
        case .pen: "p"
        case .mosaic: "m"
        }
    }
}

enum StrokeWidth: Int, CaseIterable, Identifiable {
    case thin = 2, medium = 4, thick = 7
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .thin: String(localized: "Thin")
        case .medium: String(localized: "Medium")
        case .thick: String(localized: "Thick")
        }
    }
}

enum LineStyle: String, CaseIterable, Identifiable {
    case solid, dashed
    var id: String { rawValue }
    var title: String {
        switch self {
        case .solid: String(localized: "Solid")
        case .dashed: String(localized: "Dashed")
        }
    }
}

/// 書き込みに使える色。macOS のシステムカラーをもとに、黒と白を加えたもの。
struct PaletteColor: Identifiable {
    let name: String
    let color: NSColor
    var id: String { name }

    private init(_ name: String, _ hex: UInt32) {
        self.name = name
        color = NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255,
                        green: CGFloat(hex >> 8 & 0xFF) / 255,
                        blue: CGFloat(hex & 0xFF) / 255,
                        alpha: 1)
    }

    static let all: [PaletteColor] = [
        PaletteColor(String(localized: "Red"), 0xFF5257),
        PaletteColor(String(localized: "Orange"), 0xF7821B),
        PaletteColor(String(localized: "Yellow"), 0xFFC600),
        PaletteColor(String(localized: "Green"), 0x62BA46),
        PaletteColor(String(localized: "Blue"), 0x007AFF),
        PaletteColor(String(localized: "Purple"), 0xA550A7),
        PaletteColor(String(localized: "Pink"), 0xF74F9E),
        PaletteColor(String(localized: "Gray"), 0x8C8C8C),
        PaletteColor(String(localized: "Black"), 0x1D1D1F),
        PaletteColor(String(localized: "White"), 0xFFFFFF),
    ]
}

/// 図形。座標は画像のピクセル座標（左上原点）。
struct Annotation: Identifiable {
    enum Shape {
        case arrow(CGPoint, CGPoint)
        case line(CGPoint, CGPoint)
        case rect(CGRect)
        case ellipse(CGRect)
        case fill(CGRect)
        case mosaic(CGRect)
        case pen([CGPoint])
        case text(origin: CGPoint, string: String, fontSize: CGFloat)
    }

    var id = UUID()
    var shape: Shape
    var color: NSColor
    var lineWidth: CGFloat
    var isDashed = false
    /// 文字に縁取りをつけるか。
    var textOutlined = true

    func offsetBy(dx: CGFloat, dy: CGFloat) -> Annotation {
        var copy = self
        func p(_ pt: CGPoint) -> CGPoint { CGPoint(x: pt.x + dx, y: pt.y + dy) }
        switch shape {
        case .arrow(let a, let b): copy.shape = .arrow(p(a), p(b))
        case .line(let a, let b): copy.shape = .line(p(a), p(b))
        case .rect(let r): copy.shape = .rect(r.offsetBy(dx: dx, dy: dy))
        case .ellipse(let r): copy.shape = .ellipse(r.offsetBy(dx: dx, dy: dy))
        case .fill(let r): copy.shape = .fill(r.offsetBy(dx: dx, dy: dy))
        case .mosaic(let r): copy.shape = .mosaic(r.offsetBy(dx: dx, dy: dy))
        case .pen(let pts): copy.shape = .pen(pts.map(p))
        case .text(let o, let s, let f): copy.shape = .text(origin: p(o), string: s, fontSize: f)
        }
        return copy
    }

    var textAttributes: [NSAttributedString.Key: Any] {
        guard case .text(_, _, let fontSize) = shape else { return [:] }
        return Annotation.textAttributes(fontSize: fontSize, color: color)
    }

    static func textAttributes(fontSize: CGFloat, color: NSColor) -> [NSAttributedString.Key: Any] {
        [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .bold),
            .foregroundColor: color,
        ]
    }

    /// 縁取りだけを描く属性。文字の下に太い線として重ねる。
    static func textOutlineAttributes(fontSize: CGFloat, color: NSColor) -> [NSAttributedString.Key: Any] {
        var attributes = textAttributes(fontSize: fontSize, color: color)
        attributes[.strokeColor] = color.isLight ? NSColor.black : NSColor.white
        attributes[.strokeWidth] = 18 // フォントサイズに対する % で、正の値は線のみ
        return attributes
    }

    /// 選択判定と選択枠の表示に使う範囲。
    var bounds: CGRect {
        switch shape {
        case .arrow(let a, let b), .line(let a, let b):
            return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
        case .rect(let r), .ellipse(let r), .fill(let r), .mosaic(let r):
            return r
        case .pen(let pts):
            guard let first = pts.first else { return .zero }
            return pts.reduce(CGRect(origin: first, size: .zero)) { $0.union(CGRect(origin: $1, size: .zero)) }
        case .text(let origin, let string, _):
            let size = NSAttributedString(string: string, attributes: textAttributes).size()
            return CGRect(origin: origin, size: size)
        }
    }

    func hitTest(_ point: CGPoint, tolerance: CGFloat) -> Bool {
        let t = max(tolerance, lineWidth)
        switch shape {
        case .arrow(let a, let b), .line(let a, let b):
            return distance(point, toSegment: a, b) <= t
        case .rect(let r), .ellipse(let r):
            let outer = r.insetBy(dx: -t, dy: -t)
            let inner = r.insetBy(dx: t, dy: t)
            return outer.contains(point) && (inner.isNull || !inner.contains(point))
        case .fill(let r), .mosaic(let r):
            return r.insetBy(dx: -t, dy: -t).contains(point)
        case .pen(let pts):
            return zip(pts, pts.dropFirst()).contains { distance(point, toSegment: $0, $1) <= t }
        case .text:
            return bounds.insetBy(dx: -t, dy: -t).contains(point)
        }
    }

    private func distance(_ p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let len2 = dx * dx + dy * dy
        guard len2 > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }
}

extension NSColor {
    var isLight: Bool {
        guard let c = usingColorSpace(.sRGB) else { return false }
        return 0.299 * c.redComponent + 0.587 * c.greenComponent + 0.114 * c.blueComponent > 0.7
    }
}

/// 図形を CGContext に描く。表示と書き出しで同じ処理を使う。
/// コンテキストは画像のピクセル座標・左上原点（y 下向き）に合わせてから渡すこと。
enum AnnotationRenderer {
    static func drawImage(_ image: CGImage, in ctx: CGContext, rect: CGRect) {
        ctx.saveGState()
        ctx.translateBy(x: rect.minX, y: rect.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(image, in: CGRect(origin: .zero, size: rect.size))
        ctx.restoreGState()
    }

    static func draw(_ annotation: Annotation, in ctx: CGContext, imageSize: CGSize, mosaicImage: CGImage?) {
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.setStrokeColor(annotation.color.cgColor)
        ctx.setFillColor(annotation.color.cgColor)
        ctx.setLineWidth(annotation.lineWidth)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        if annotation.isDashed {
            // 線端が丸いので、隙間は線幅より広くする
            ctx.setLineDash(phase: 0, lengths: [annotation.lineWidth * 2.2, annotation.lineWidth * 2.4])
        }

        switch annotation.shape {
        case .line(let a, let b):
            ctx.move(to: a)
            ctx.addLine(to: b)
            ctx.strokePath()

        case .arrow(let a, let b):
            let length = hypot(b.x - a.x, b.y - a.y)
            guard length > 0 else { return }
            let ux = (b.x - a.x) / length, uy = (b.y - a.y) / length
            /// 先端から軸に沿って along、軸の横に side だけ離れた点。
            func point(_ along: CGFloat, _ side: CGFloat) -> CGPoint {
                CGPoint(x: b.x - ux * along - uy * side, y: b.y - uy * along + ux * side)
            }
            let w = annotation.lineWidth
            let headLength = min(max(w * 5.5, 16), length * 0.6)
            let headHalfWidth = headLength * 0.5
            // 返しより先端側をくびれさせて、矢じりを後ろに流す
            let neck = headLength * 0.72
            let neckHalfWidth = max(w * 0.6, 1.2)
            let tailHalfWidth = w * 0.1

            if annotation.isDashed {
                ctx.move(to: a)
                ctx.addLine(to: point(neck, 0))
                ctx.strokePath()
                ctx.setLineDash(phase: 0, lengths: [])
            }
            ctx.move(to: b)
            ctx.addLine(to: point(headLength, headHalfWidth))
            ctx.addLine(to: point(neck, neckHalfWidth))
            if !annotation.isDashed {
                // 根元に向かって細くなる軸
                ctx.addLine(to: point(length, tailHalfWidth))
                ctx.addLine(to: point(length, -tailHalfWidth))
            }
            ctx.addLine(to: point(neck, -neckHalfWidth))
            ctx.addLine(to: point(headLength, -headHalfWidth))
            ctx.closePath()
            // 細い線を重ねて角を少し丸める
            ctx.setLineWidth(max(w * 0.2, 1))
            ctx.drawPath(using: .fillStroke)

        case .rect(let r):
            let rect = r.standardized
            let radius = min(annotation.lineWidth * 2, min(rect.width, rect.height) / 2)
            ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
            ctx.strokePath()

        case .ellipse(let r):
            ctx.strokeEllipse(in: r.standardized)

        case .fill(let r):
            ctx.fill(r.standardized)

        case .mosaic(let r):
            guard let mosaicImage else { return }
            ctx.clip(to: r.standardized)
            drawImage(mosaicImage, in: ctx, rect: CGRect(origin: .zero, size: imageSize))

        case .pen(let pts):
            guard let first = pts.first else { return }
            ctx.move(to: first)
            if pts.count == 1 {
                ctx.addLine(to: first)
            } else {
                // 中点を通る二次曲線でなめらかにする
                for i in 1..<pts.count {
                    let mid = CGPoint(x: (pts[i - 1].x + pts[i].x) / 2, y: (pts[i - 1].y + pts[i].y) / 2)
                    ctx.addQuadCurve(to: mid, control: pts[i - 1])
                }
                ctx.addLine(to: pts[pts.count - 1])
            }
            ctx.strokePath()

        case .text(let origin, let string, let fontSize):
            let previous = NSGraphicsContext.current
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
            if annotation.textOutlined {
                let outline = Annotation.textOutlineAttributes(fontSize: fontSize, color: annotation.color)
                NSAttributedString(string: string, attributes: outline).draw(at: origin)
            }
            NSAttributedString(string: string, attributes: annotation.textAttributes).draw(at: origin)
            NSGraphicsContext.current = previous
        }
    }

    /// モザイク用に、画像全体を「ブロックごとの平均色」で塗ったものを作る。
    static func makeMosaicImage(from image: CGImage, blockSize: CGFloat) -> CGImage? {
        let width = image.width, height = image.height
        let block = max(1, Int(blockSize.rounded()))
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = ctx.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let bytesPerRow = ctx.bytesPerRow

        // 箱型フィルタをかけると、各点の値が周囲のブロック分の平均になる。カーネルは奇数のみ。
        let averaged = UnsafeMutablePointer<UInt8>.allocate(capacity: bytesPerRow * height)
        defer { averaged.deallocate() }
        var source = vImage_Buffer(data: data, height: vImagePixelCount(height),
                                   width: vImagePixelCount(width), rowBytes: bytesPerRow)
        var destination = vImage_Buffer(data: averaged, height: vImagePixelCount(height),
                                        width: vImagePixelCount(width), rowBytes: bytesPerRow)
        let kernel = UInt32(block | 1)
        guard vImageBoxConvolve_ARGB8888(&source, &destination, nil, 0, 0, kernel, kernel, nil,
                                         vImage_Flags(kvImageEdgeExtend)) == kvImageNoError else { return nil }

        // ブロックの中心の平均値で、ブロック全体を塗る
        for blockY in stride(from: 0, to: height, by: block) {
            let maxY = min(blockY + block, height)
            let centerY = (blockY + maxY) / 2
            for blockX in stride(from: 0, to: width, by: block) {
                let maxX = min(blockX + block, width)
                let center = averaged + centerY * bytesPerRow + (blockX + maxX) / 2 * 4
                for y in blockY..<maxY {
                    memset_pattern4(data + y * bytesPerRow + blockX * 4, center, (maxX - blockX) * 4)
                }
            }
        }
        return ctx.makeImage()
    }

    /// 書き出し用に、注釈を焼き込んだ画像を作る。
    static func render(base: CGImage, annotations: [Annotation], mosaicImage: CGImage?) -> CGImage? {
        let size = CGSize(width: base.width, height: base.height)
        guard let ctx = CGContext(data: nil, width: base.width, height: base.height, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.translateBy(x: 0, y: size.height)
        ctx.scaleBy(x: 1, y: -1)
        drawImage(base, in: ctx, rect: CGRect(origin: .zero, size: size))
        for a in annotations {
            draw(a, in: ctx, imageSize: size, mosaicImage: mosaicImage)
        }
        return ctx.makeImage()
    }
}
