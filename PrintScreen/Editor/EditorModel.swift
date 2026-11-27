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
    var color: NSColor = PaletteColor.all[0].color {
        didSet { applyToSelection { $0.color = color } }
    }
    var lineStyle: LineStyle = .solid {
        didSet {
            let dashed = lineStyle == .dashed
            applyToSelection { a in
                if case .text = a.shape { return }
                a.isDashed = dashed
            }
        }
    }
    /// 次に入力する文字に縁取りをつけるか。最後に切り替えた状態を引き継ぐ。
    @ObservationIgnored var textOutlined = true
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
    /// この画像の保存形式。初期値は設定の形式で、変えても設定には残さない。
    var format: ImageFormat = AppSettings.shared.imageFormat
    /// 保存済みかどうか（閉じるときの確認用）
    var isSaved = false

    /// 文字を入力中かどうか。入力中は ⌘Z や ⌘C を入力欄に渡す。
    var isEditingText = false

    @ObservationIgnored var canvasNeedsDisplay: (() -> Void)?
    /// 入力中の文字を確定する。
    @ObservationIgnored var finishTextEditing: (() -> Void)?
    // canUndo / canRedo でボタンの有効状態を更新するので、監視の対象にする
    private var undoStack: [[Annotation]] = []
    private var redoStack: [[Annotation]] = []

    init(image: CGImage, pixelScale: CGFloat) {
        self.image = image
        self.pixelScale = pixelScale
        self.mosaicImage = AnnotationRenderer.makeMosaicImage(from: image, blockSize: 7 * pixelScale)
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

    /// Esc。選択ツールに切り替え、すでに選択ツールなら選択を解除する。
    func handleEscape() {
        if tool != .select {
            tool = .select
        } else {
            selectedID = nil
        }
    }

    /// 選択中の文字の縁取りを切り替える。
    func toggleSelectedTextOutline() {
        guard let id = selectedID,
              let current = annotations.first(where: { $0.id == id }),
              case .text = current.shape else { return }
        let outlined = !current.textOutlined
        checkpoint()
        update(id) { $0.textOutlined = outlined }
        textOutlined = outlined
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
