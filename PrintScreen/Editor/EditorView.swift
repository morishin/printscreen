import AppKit
import SwiftUI

struct EditorView: View {
    @Bindable var model: EditorModel
    var onCopy: () -> Void
    var onSave: () -> Void
    var onDiscard: () -> Void

    /// ツールバーの項目がオーバーフローメニューに入らない幅。
    static let minimumWidth: CGFloat = 960

    var body: some View {
        AnnotationCanvas(model: model)
            .frame(minWidth: EditorView.minimumWidth, minHeight: 280)
            .background(Color(nsColor: .underPageBackgroundColor))
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Picker("ツール", selection: $model.tool) {
                        ForEach(EditorTool.allCases) { tool in
                            Label(tool.title, systemImage: tool.symbol)
                                .help("\(tool.title)（\(tool.key.uppercased())）")
                                .tag(tool)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelStyle(.iconOnly)
                }
                ToolbarItem {
                    ColorPaletteButton(selection: $model.color)
                }
                ToolbarItem {
                    Picker("太さ", selection: $model.strokeWidth) {
                        ForEach(StrokeWidth.allCases) { w in
                            Image(nsImage: LineIcon.width(w))
                                .accessibilityLabel(w.title)
                                .tag(w)
                        }
                    }
                    .pickerStyle(.segmented)
                    .help("線の太さ・文字の大きさ")
                }
                ToolbarItem {
                    Picker("線の種類", selection: $model.lineStyle) {
                        ForEach(LineStyle.allCases) { style in
                            Image(nsImage: LineIcon.style(style))
                                .accessibilityLabel(style.title)
                                .tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                    .help("実線・破線")
                }
                ToolbarItemGroup {
                    Button("取り消す", systemImage: "arrow.uturn.backward") { model.undo() }
                        .keyboardShortcut("z", modifiers: .command)
                        .disabled(!model.canUndo || model.isEditingText)
                        .help("取り消す（⌘Z）")
                    Button("やり直す", systemImage: "arrow.uturn.forward") { model.redo() }
                        .keyboardShortcut("z", modifiers: [.command, .shift])
                        .disabled(!model.canRedo || model.isEditingText)
                        .help("やり直す（⇧⌘Z）")
                }
                ToolbarSpacer(.fixed)
                ToolbarItemGroup {
                    Button("破棄", systemImage: "trash") { onDiscard() }
                        .help("保存せずに閉じる（⌘W）")
                    Button("コピー", systemImage: "doc.on.doc") { onCopy() }
                        // 文字の入力中は ⌘C を入力欄に渡す
                        .keyboardShortcut(model.isEditingText ? nil : KeyboardShortcut("c", modifiers: .command))
                        .help("クリップボードにコピー（⌘C）")
                    Button { onSave() } label: {
                        Text("保存  ⌘S")
                    }
                        .keyboardShortcut("s", modifiers: .command)
                        .buttonStyle(.borderedProminent)
                        .help("保存して閉じる（⌘S）")
                }
            }
    }

}

/// 今の色を示すボタン。押すとパレットを開く。
private struct ColorPaletteButton: View {
    @Binding var selection: NSColor
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Circle()
                .fill(Color(nsColor: selection))
                .overlay(Circle().strokeBorder(.secondary.opacity(0.6), lineWidth: 1))
                .frame(width: 16, height: 16)
        }
        .help("色")
        .accessibilityLabel("色")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            ColorPaletteGrid(selection: $selection) { isPresented = false }
        }
    }
}

struct ColorPaletteGrid: View {
    @Binding var selection: NSColor
    var onSelect: () -> Void

    private let columns = Array(repeating: GridItem(.fixed(30), spacing: 8), count: 5)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(PaletteColor.all) { item in
                Button {
                    selection = item.color
                    onSelect()
                } label: {
                    Circle()
                        .fill(Color(nsColor: item.color))
                        .overlay(Circle().strokeBorder(.secondary.opacity(0.5), lineWidth: 0.5))
                        .frame(width: 24, height: 24)
                        .padding(3)
                        .overlay {
                            if selection == item.color {
                                Circle().strokeBorder(Color(nsColor: item.color), lineWidth: 2)
                            }
                        }
                }
                .buttonStyle(.plain)
                .help(item.name)
                .accessibilityLabel(item.name)
            }
        }
        .padding(12)
    }
}

/// 線の太さと種類を示すアイコン。文字色に合わせて描かれる。
enum LineIcon {
    static func width(_ width: StrokeWidth) -> NSImage {
        let thickness: CGFloat = switch width {
        case .thin: 1.5
        case .medium: 3
        case .thick: 5.5
        }
        return make(accessibility: width.title) { rect in
            let bar = CGRect(x: rect.minX, y: rect.midY - thickness / 2, width: rect.width, height: thickness)
            NSBezierPath(roundedRect: bar, xRadius: thickness / 2, yRadius: thickness / 2).fill()
        }
    }

    static func style(_ style: LineStyle) -> NSImage {
        make(accessibility: style.title) { rect in
            let path = NSBezierPath()
            path.move(to: CGPoint(x: rect.minX + 1, y: rect.midY))
            path.line(to: CGPoint(x: rect.maxX - 1, y: rect.midY))
            path.lineWidth = 2.5
            path.lineCapStyle = .round
            if style == .dashed {
                path.setLineDash([3.5, 5], count: 2, phase: 0)
            }
            path.stroke()
        }
    }

    private static func make(accessibility: String, _ draw: @escaping (CGRect) -> Void) -> NSImage {
        let image = NSImage(size: NSSize(width: 22, height: 14), flipped: false) { rect in
            NSColor.black.set()
            draw(rect)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = accessibility
        return image
    }
}
