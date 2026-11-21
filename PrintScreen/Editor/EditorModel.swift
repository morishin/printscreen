import AppKit
import Observation

@Observable
final class EditorModel {
    let image: CGImage
    /// 1 ポイントあたりのピクセル数（Retina なら 2）
    let pixelScale: CGFloat
    @ObservationIgnored let mosaicImage: CGImage?

    var annotations: [Annotation] = [] { didSet { canvasNeedsDisplay?() } }
    var selectedID: UUID? { didSet { canvasNeedsDisplay?() } }
    var tool: EditorTool = .arrow {
        didSet { if tool != .select { selectedID = nil } }
    }
    var color: NSColor = .systemRed {
        didSet { applyToSelection { $0.color = color } }
    }
    var strokeWidth: StrokeWidth = .medium {
        didSet {
            let width = lineWidth(for: strokeWidth)
            let fontSize = currentFontSize
            applyToSelection { a in
                a.lineWidth = width
                if case .text(let origin, let string, _) = a.shape {
                    a.shape = .text(origin: origin, string: string, fontSize: fontSize)
                }
            }
        }
    }
    /// 保存済みかどうか（閉じるときの確認用）
    var isSaved = false

    @ObservationIgnored var canvasNeedsDisplay: (() -> Void)?
    @ObservationIgnored private var undoStack: [[Annotation]] = []
    @ObservationIgnored private var redoStack: [[Annotation]] = []

    static let palette: [NSColor] = [
        .systemRed, .systemOrange, .systemYellow, .systemGreen, .systemBlue, .systemPurple, .black, .white,
    ]

    init(image: CGImage, pixelScale: CGFloat) {
        self.image = image
        self.pixelScale = pixelScale
        self.mosaicImage = AnnotationRenderer.makeMosaicImage(from: image, blockSize: 10 * pixelScale)
    }

    var imageSize: CGSize { CGSize(width: image.width, height: image.height) }

    func lineWidth(for width: StrokeWidth) -> CGFloat { CGFloat(width.rawValue) * pixelScale }
    var currentLineWidth: CGFloat { lineWidth(for: strokeWidth) }
    var currentFontSize: CGFloat { (12 + CGFloat(strokeWidth.rawValue) * 3) * pixelScale }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    /// 変更の前に呼んで、元に戻せるようにする。
    func checkpoint() {
        undoStack.append(annotations)
        redoStack.removeAll()
        isSaved = false
    }

    func undo() {
        guard let last = undoStack.popLast() else { return }
        redoStack.append(annotations)
        annotations = last
        selectedID = nil
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(annotations)
        annotations = next
        selectedID = nil
    }

    func add(_ annotation: Annotation) {
        checkpoint()
        annotations.append(annotation)
    }

    func deleteSelection() {
        guard let id = selectedID else { return }
        checkpoint()
        annotations.removeAll { $0.id == id }
        selectedID = nil
    }

    func annotation(at point: CGPoint) -> Annotation? {
        annotations.last { $0.hitTest(point, tolerance: 6 * pixelScale) }
    }

    func update(_ id: UUID, _ body: (inout Annotation) -> Void) {
        guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        body(&annotations[index])
    }

    private func applyToSelection(_ body: (inout Annotation) -> Void) {
        guard let id = selectedID else { return }
        checkpoint()
        update(id, body)
    }

    func renderedImage() -> CGImage? {
        AnnotationRenderer.render(base: image, annotations: annotations, mosaicImage: mosaicImage)
    }
}
