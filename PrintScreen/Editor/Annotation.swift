import AppKit

enum EditorTool: String, CaseIterable, Identifiable {
    case select, arrow, line, rect, ellipse, fill, text, pen, mosaic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .select: "選択"
        case .arrow: "矢印"
        case .line: "線"
        case .rect: "枠"
        case .ellipse: "楕円"
        case .fill: "塗りつぶし"
        case .text: "文字"
        case .pen: "ペン"
        case .mosaic: "モザイク"
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
        case .text: "textformat"
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
        case .thin: "細"
        case .medium: "中"
        case .thick: "太"
        }
    }
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
            .strokeColor: color.isLight ? NSColor.black : NSColor.white,
            .strokeWidth: -2.5,
        ]
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
        return 0.299 * c.redComponent + 0.587 * c.greenComponent + 0.114 * c.blueComponent > 0.6
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

        switch annotation.shape {
        case .line(let a, let b):
            ctx.move(to: a)
            ctx.addLine(to: b)
            ctx.strokePath()

        case .arrow(let a, let b):
            let angle = atan2(b.y - a.y, b.x - a.x)
            let length = hypot(b.x - a.x, b.y - a.y)
            let headLength = min(max(annotation.lineWidth * 4.5, 14), length * 0.6)
            let headWidth = headLength * 0.65
            // 軸は矢じりの根元まで
            let base = CGPoint(x: b.x - cos(angle) * headLength * 0.8, y: b.y - sin(angle) * headLength * 0.8)
            ctx.move(to: a)
            ctx.addLine(to: base)
            ctx.strokePath()
            let left = CGPoint(x: b.x - cos(angle) * headLength + sin(angle) * headWidth,
                               y: b.y - sin(angle) * headLength - cos(angle) * headWidth)
            let right = CGPoint(x: b.x - cos(angle) * headLength - sin(angle) * headWidth,
                                y: b.y - sin(angle) * headLength + cos(angle) * headWidth)
            ctx.move(to: b)
            ctx.addLine(to: left)
            ctx.addLine(to: right)
            ctx.closePath()
            ctx.fillPath()

        case .rect(let r):
            ctx.stroke(r.standardized)

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

        case .text(let origin, let string, _):
            let previous = NSGraphicsContext.current
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
            NSAttributedString(string: string, attributes: annotation.textAttributes).draw(at: origin)
            NSGraphicsContext.current = previous
        }
    }

    /// モザイク用に、画像全体をピクセル化したものを作る。
    static func makeMosaicImage(from image: CGImage, blockSize: CGFloat) -> CGImage? {
        let ci = CIImage(cgImage: image)
        guard let filter = CIFilter(name: "CIPixellate") else { return nil }
        filter.setValue(ci.clampedToExtent(), forKey: kCIInputImageKey)
        filter.setValue(blockSize, forKey: kCIInputScaleKey)
        filter.setValue(CIVector(x: 0, y: 0), forKey: kCIInputCenterKey)
        guard let output = filter.outputImage?.cropped(to: ci.extent) else { return nil }
        return CIContext().createCGImage(output, from: ci.extent)
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
