import AppKit
import SwiftUI

struct EditorView: View {
    @Bindable var model: EditorModel
    var onCopy: () -> Void
    var onSave: () -> Void
    var onDiscard: () -> Void

    var body: some View {
        AnnotationCanvas(model: model)
            .frame(minWidth: 480, minHeight: 280)
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
                    Menu {
                        ForEach(EditorModel.palette, id: \.self) { color in
                            Button {
                                model.color = color
                            } label: {
                                Label {
                                    Text(color.localizedName)
                                } icon: {
                                    Image(nsImage: swatch(color))
                                }
                            }
                        }
                    } label: {
                        Image(nsImage: swatch(model.color))
                    }
                    .help("色")
                }
                ToolbarItem {
                    Picker("太さ", selection: $model.strokeWidth) {
                        ForEach(StrokeWidth.allCases) { w in
                            Text(w.title).tag(w)
                        }
                    }
                    .pickerStyle(.segmented)
                    .help("線の太さ・文字の大きさ")
                }
                ToolbarItemGroup {
                    Button("取り消す", systemImage: "arrow.uturn.backward") { model.undo() }
                        .keyboardShortcut("z", modifiers: .command)
                        .disabled(!model.canUndo)
                    Button("やり直す", systemImage: "arrow.uturn.forward") { model.redo() }
                        .keyboardShortcut("z", modifiers: [.command, .shift])
                        .disabled(!model.canRedo)
                }
                ToolbarSpacer(.fixed)
                ToolbarItemGroup {
                    Button("破棄", systemImage: "trash") { onDiscard() }
                        .help("保存せずに閉じる")
                    Button("コピー", systemImage: "doc.on.doc") { onCopy() }
                        .keyboardShortcut("c", modifiers: .command)
                        .help("クリップボードにコピー（⌘C）")
                    Button("保存", systemImage: "square.and.arrow.down") { onSave() }
                        .keyboardShortcut("s", modifiers: .command)
                        .buttonStyle(.borderedProminent)
                        .help("保存して閉じる（⌘S）")
                }
            }
    }

    private func swatch(_ color: NSColor) -> NSImage {
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            color.setFill()
            let path = NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1))
            path.fill()
            NSColor.gray.withAlphaComponent(0.6).setStroke()
            path.lineWidth = 1
            path.stroke()
            return true
        }
        return image
    }
}

extension NSColor {
    var localizedName: String {
        switch self {
        case .systemRed: "赤"
        case .systemOrange: "オレンジ"
        case .systemYellow: "黄"
        case .systemGreen: "緑"
        case .systemBlue: "青"
        case .systemPurple: "紫"
        case .black: "黒"
        case .white: "白"
        default: "色"
        }
    }
}
