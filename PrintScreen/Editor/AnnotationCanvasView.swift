import AppKit
import SwiftUI

struct AnnotationCanvas: NSViewRepresentable {
    let model: EditorModel

    func makeNSView(context: Context) -> AnnotationCanvasView {
        let view = AnnotationCanvasView(model: model)
        model.canvasNeedsDisplay = { [weak view] in view?.needsDisplay = true }
        model.finishTextEditing = { [weak view] in view?.commitText() }
        return view
    }

    func updateNSView(_ nsView: AnnotationCanvasView, context: Context) {
        _ = model.tool
        nsView.window?.invalidateCursorRects(for: nsView)
        nsView.needsDisplay = true
    }
}

/// 画像と注釈を描き、マウス操作で注釈を作る。
final class AnnotationCanvasView: NSView, NSTextFieldDelegate {
    private let model: EditorModel
    /// ドラッグ中の図形
    private var draft: Annotation?
    private var dragStart: CGPoint?
    private var moveOrigin: CGPoint?
    private var movingOriginal: Annotation?
    private var textField: NSTextField?
    /// 編集中のテキスト注釈（既存のものを編集しているとき）
    private var editingTextID: UUID?
    private var editingTextOrigin: CGPoint = .zero

    init(model: EditorModel) {
        self.model = model
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // 開いた直後から Esc やツールのキーを受け取る
        window?.makeFirstResponder(self)
    }

    // MARK: 座標変換

    /// 画像を表示する領域（アスペクト比を保って中央に配置）
    private var imageRect: CGRect {
        let size = model.imageSize
        let inset = bounds.insetBy(dx: 12, dy: 12)
        let scale = min(inset.width / size.width, inset.height / size.height, 1 / model.pixelScale * 1)
        let w = size.width * scale, h = size.height * scale
        return CGRect(x: bounds.midX - w / 2, y: bounds.midY - h / 2, width: w, height: h)
    }

    /// 表示上の 1 ポイントが画像の何ピクセルか
    private var viewScale: CGFloat { imageRect.width / model.imageSize.width }

    private func toImage(_ p: CGPoint) -> CGPoint {
        let r = imageRect
        return CGPoint(x: (p.x - r.minX) / viewScale, y: (p.y - r.minY) / viewScale)
    }

    private func toView(_ p: CGPoint) -> CGPoint {
        let r = imageRect
        return CGPoint(x: r.minX + p.x * viewScale, y: r.minY + p.y * viewScale)
    }

    private func clampToImage(_ p: CGPoint) -> CGPoint {
        CGPoint(x: min(max(0, p.x), model.imageSize.width), y: min(max(0, p.y), model.imageSize.height))
    }

    // MARK: 描画

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let r = imageRect

        // 影
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: 2), blur: 10, color: NSColor.black.withAlphaComponent(0.35).cgColor)
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(r)
        ctx.restoreGState()

        ctx.saveGState()
        ctx.clip(to: r)
        ctx.translateBy(x: r.minX, y: r.minY)
        ctx.scaleBy(x: viewScale, y: viewScale)
        ctx.interpolationQuality = .high
        AnnotationRenderer.drawImage(model.image, in: ctx, rect: CGRect(origin: .zero, size: model.imageSize))
        for a in model.annotations where a.id != editingTextID {
            AnnotationRenderer.draw(a, in: ctx, imageSize: model.imageSize, mosaicImage: model.mosaicImage)
        }
        if let draft {
            AnnotationRenderer.draw(draft, in: ctx, imageSize: model.imageSize, mosaicImage: model.mosaicImage)
            if case .mosaic(let rect) = draft.shape {
                ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.8).cgColor)
                ctx.setLineWidth(1 / viewScale)
                ctx.setLineDash(phase: 0, lengths: [4 / viewScale, 4 / viewScale])
                ctx.stroke(rect.standardized)
            }
        }
        ctx.restoreGState()

        // 選択枠
        if let viewRect = selectionViewRect {
            ctx.saveGState()
            ctx.setStrokeColor(NSColor.controlAccentColor.cgColor)
            ctx.setLineWidth(1.5)
            ctx.setLineDash(phase: 0, lengths: [5, 3])
            ctx.stroke(viewRect)
            ctx.restoreGState()
        }
        drawTextOutlineButton()
    }

    private var selectedAnnotation: Annotation? {
        guard let id = model.selectedID else { return nil }
        return model.annotations.first { $0.id == id }
    }

    /// 選択枠（ビュー座標）。
    private var selectionViewRect: CGRect? {
        guard let a = selectedAnnotation else { return nil }
        let b = a.bounds.standardized
        return CGRect(origin: toView(b.origin), size: CGSize(width: b.width * viewScale, height: b.height * viewScale))
            .insetBy(dx: -5, dy: -5)
    }

    /// 選択中の文字の上に出す、縁取り切り替えボタンの位置。上に余裕がなければ下に出す。
    private var textOutlineButtonRect: CGRect? {
        guard let a = selectedAnnotation, case .text = a.shape, let frame = selectionViewRect else { return nil }
        let size: CGFloat = 24
        let y = frame.minY - size - 6 >= bounds.minY + 2 ? frame.minY - size - 6 : frame.maxY + 6
        return CGRect(x: frame.midX - size / 2, y: y, width: size, height: size)
    }

    private func drawTextOutlineButton() {
        guard let rect = textOutlineButtonRect, let a = selectedAnnotation else { return }
        let circle = NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1))
        (a.textOutlined ? NSColor.controlAccentColor : NSColor.white).setFill()
        circle.fill()
        NSColor.controlAccentColor.setStroke()
        circle.lineWidth = 1.5
        circle.stroke()
        let label = NSAttributedString(string: "a", attributes: [
            .font: NSFont.systemFont(ofSize: 15, weight: .bold),
            .foregroundColor: a.textOutlined ? NSColor.white : NSColor.controlAccentColor,
        ])
        let size = label.size()
        label.draw(at: CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2 - 1))
    }

    override func resetCursorRects() {
        let cursor: NSCursor = switch model.tool {
        case .select: .arrow
        case .text: .iBeam
        default: .crosshair
        }
        addCursorRect(imageRect, cursor: cursor)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        repositionTextField()
        window?.invalidateCursorRects(for: self)
    }

    // MARK: マウス

    override func mouseDown(with event: NSEvent) {
        let viewPoint = convert(event.locationInWindow, from: nil)
        let p = toImage(viewPoint)

        if let rect = textOutlineButtonRect, rect.contains(viewPoint) {
            model.toggleSelectedTextOutline()
            window?.makeFirstResponder(self)
            return
        }

        if textField != nil {
            commitText()
            if model.tool == .text { return }
        }

        switch model.tool {
        case .select:
            if let hit = model.annotation(at: p) {
                model.selectedID = hit.id
                if event.clickCount == 2, case .text = hit.shape {
                    beginEditingText(hit)
                    return
                }
                moveOrigin = p
                movingOriginal = hit
            } else {
                model.selectedID = nil
            }
        case .text:
            // 既存の文字をクリックしたら編集
            if let hit = model.annotation(at: p), case .text = hit.shape {
                beginEditingText(hit)
                return
            } else if imageRect.contains(viewPoint) {
                beginNewText(at: p)
                return // 下でフォーカスを戻すと入力欄が閉じてしまう
            }
        default:
            guard imageRect.contains(viewPoint) else { return }
            let start = clampToImage(p)
            dragStart = start
            draft = makeShape(from: start, to: start)
        }
        window?.makeFirstResponder(self)
    }

    override func mouseDragged(with event: NSEvent) {
        let p = toImage(convert(event.locationInWindow, from: nil))
        if let moveOrigin, let movingOriginal {
            if model.selectedID == movingOriginal.id, self.movingOriginal != nil {
                let moved = movingOriginal.offsetBy(dx: p.x - moveOrigin.x, dy: p.y - moveOrigin.y)
                if !didCheckpointForMove {
                    model.checkpoint()
                    didCheckpointForMove = true
                }
                model.update(movingOriginal.id) { $0 = moved }
            }
            return
        }
        guard let dragStart else { return }
        var end = clampToImage(p)
        if event.modifierFlags.contains(.shift) { end = constrain(from: dragStart, to: end) }
        if case .pen(let pts) = draft?.shape {
            draft?.shape = .pen(pts + [end])
        } else {
            draft = makeShape(from: dragStart, to: end, id: draft?.id)
        }
        needsDisplay = true
    }

    private var didCheckpointForMove = false

    override func mouseUp(with event: NSEvent) {
        defer {
            dragStart = nil
            draft = nil
            moveOrigin = nil
            movingOriginal = nil
            didCheckpointForMove = false
            needsDisplay = true
        }
        guard let draft else { return }
        if isMeaningful(draft) { model.add(draft) }
    }

    override func keyDown(with event: NSEvent) {
        switch Int(event.keyCode) {
        case 51, 117: // delete, forward delete
            model.deleteSelection()
        case 53: // esc
            model.handleEscape()
        default:
            // 修飾キーなしの 1 文字でツールを切り替える
            if event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
               let chars = event.charactersIgnoringModifiers?.lowercased(),
               let tool = EditorTool.allCases.first(where: { $0.key == chars }) {
                model.tool = tool
            } else {
                super.keyDown(with: event)
            }
        }
    }

    // MARK: 図形

    private func makeShape(from a: CGPoint, to b: CGPoint, id: UUID? = nil) -> Annotation {
        let rect = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
        let shape: Annotation.Shape = switch model.tool {
        case .arrow: .arrow(a, b)
        case .line: .line(a, b)
        case .rect: .rect(rect)
        case .ellipse: .ellipse(rect)
        case .fill: .fill(rect)
        case .mosaic: .mosaic(rect)
        case .pen: .pen([a, b])
        case .select, .text: .line(a, b)
        }
        var annotation = Annotation(shape: shape, color: model.color, lineWidth: model.currentLineWidth,
                                    isDashed: model.lineStyle == .dashed)
        if let id { annotation.id = id }
        return annotation
    }

    /// Shift を押しながらのとき、線は 45 度刻み、四角は正方形にする。
    private func constrain(from a: CGPoint, to b: CGPoint) -> CGPoint {
        let dx = b.x - a.x, dy = b.y - a.y
        switch model.tool {
        case .arrow, .line:
            let angle = (atan2(dy, dx) / (.pi / 4)).rounded() * (.pi / 4)
            let len = hypot(dx, dy)
            return CGPoint(x: a.x + cos(angle) * len, y: a.y + sin(angle) * len)
        case .rect, .ellipse, .fill, .mosaic:
            let side = max(abs(dx), abs(dy))
            return CGPoint(x: a.x + (dx < 0 ? -side : side), y: a.y + (dy < 0 ? -side : side))
        default:
            return b
        }
    }

    private func isMeaningful(_ a: Annotation) -> Bool {
        let minSize = 3 * model.pixelScale
        switch a.shape {
        case .pen(let pts): return pts.count > 1
        case .arrow(let p, let q), .line(let p, let q): return hypot(p.x - q.x, p.y - q.y) > minSize
        default: return a.bounds.width > minSize || a.bounds.height > minSize
        }
    }

    // MARK: 文字入力

    private func beginNewText(at p: CGPoint) {
        editingTextID = nil
        editingTextOrigin = p
        showTextField(string: "", fontSize: model.currentFontSize, color: model.color)
    }

    private func beginEditingText(_ annotation: Annotation) {
        guard case .text(let origin, let string, let fontSize) = annotation.shape else { return }
        editingTextID = annotation.id
        editingTextOrigin = origin
        showTextField(string: string, fontSize: fontSize, color: annotation.color)
        needsDisplay = true
    }

    private func showTextField(string: String, fontSize: CGFloat, color: NSColor) {
        model.selectedID = nil
        let field = NSTextField(string: string)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.isEditable = true
        field.usesSingleLineMode = false
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.font = NSFont.systemFont(ofSize: fontSize * viewScale, weight: .bold)
        field.textColor = color
        field.delegate = self
        field.placeholderString = "文字を入力"
        addSubview(field)
        textField = field
        model.isEditingText = true
        textFontSize = fontSize
        repositionTextField()
        window?.makeFirstResponder(field)
    }

    private var textFontSize: CGFloat = 0

    private func repositionTextField() {
        guard let field = textField else { return }
        field.font = NSFont.systemFont(ofSize: textFontSize * viewScale, weight: .bold)
        field.sizeToFit()
        let origin = toView(editingTextOrigin)
        field.frame = CGRect(x: origin.x - 2, y: origin.y, width: max(field.frame.width + 20, 80), height: field.frame.height)
    }

    func controlTextDidChange(_ obj: Notification) {
        repositionTextField()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.insertNewline(_:)) {
            // Return で確定、Shift+Return で改行
            if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                textView.insertNewlineIgnoringFieldEditor(nil)
                return true
            }
            commitText()
            return true
        }
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            commitText()
            model.tool = .select
            return true
        }
        return false
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        commitText()
    }

    func commitText() {
        guard let field = textField else { return }
        textField = nil
        model.isEditingText = false
        let string = field.stringValue
        field.delegate = nil
        field.removeFromSuperview()
        if let id = editingTextID {
            model.checkpoint()
            if string.isEmpty {
                model.annotations.removeAll { $0.id == id }
            } else {
                let fontSize = textFontSize
                let origin = editingTextOrigin
                model.update(id) {
                    $0.shape = .text(origin: origin, string: string, fontSize: fontSize)
                }
                model.selectedID = id
            }
        } else if !string.isEmpty {
            let annotation = Annotation(shape: .text(origin: editingTextOrigin, string: string, fontSize: textFontSize),
                                        color: model.color, lineWidth: model.currentLineWidth,
                                        textOutlined: model.textOutlined)
            model.add(annotation)
            // 確定したら選択して、縁取りのボタンを出す
            model.selectedID = annotation.id
        }
        editingTextID = nil
        window?.makeFirstResponder(self)
        needsDisplay = true
    }
}
