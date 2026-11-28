import AppKit
import SwiftUI

/// マウスカーソルの近くに短い通知を出す。ファイルがあればクリックで Finder に表示する。
/// 時間のかかる処理の間は、くるくるか進み具合のバーを出しておける。
enum Toast {
    private static var panel: NSPanel?
    private static var hideWork: DispatchWorkItem?
    private static var content: ToastContent?

    static func show(_ message: String, detail: String? = nil, fileURL: URL? = nil, duration: TimeInterval = 4) {
        present(ToastContent(message: message, detail: detail, fileURL: fileURL, activity: nil))
        let work = DispatchWorkItem { hide() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    /// 処理中のトーストを出す。progress を渡すと進み具合のバーを出し、nil ならくるくるだけを出す。
    /// 自動では消えないので、終わったら show か hide を呼ぶ。
    /// 呼んだ直後に重い処理を同じスレッドで始めても見えるよう、その場で描画する。
    static func showActivity(_ message: String, progress: Double? = nil) {
        present(ToastContent(message: message, detail: nil, fileURL: nil, activity: .init(progress: progress)))
        panel?.display()
    }

    /// 処理中のトーストの進み具合（0〜1）を更新する。
    static func setProgress(_ progress: Double) {
        content?.activity?.progress = min(max(progress, 0), 1)
    }

    static func hide() {
        hideWork?.cancel()
        panel?.orderOut(nil)
        panel = nil
        content = nil
    }

    private static func present(_ content: ToastContent) {
        hideWork?.cancel()
        panel?.orderOut(nil)

        let view = ToastView(content: content) { hide() }
        let hosting = NSHostingView(rootView: view)
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize

        let panel = NSPanel(contentRect: CGRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = hosting
        panel.setFrameOrigin(origin(for: size))
        panel.orderFrontRegardless()
        self.panel = panel
        self.content = content
    }

    /// カーソルの右下に出す。画面からはみ出すなら左や上に回す。
    /// カーソルの真下に出すと、ボタンをうっかり押したり作業の邪魔になったりするので、少し離す。
    private static func origin(for size: CGSize) -> CGPoint {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
        let frame = screen.visibleFrame
        let offset: CGFloat = 20
        var x = mouse.x + offset
        if x + size.width > frame.maxX { x = mouse.x - offset - size.width }
        var y = mouse.y - offset - size.height
        if y < frame.minY { y = mouse.y + offset }
        x = min(max(x, frame.minX + 8), frame.maxX - size.width - 8)
        y = min(max(y, frame.minY + 8), frame.maxY - size.height - 8)
        return CGPoint(x: x, y: y)
    }
}

@Observable
private final class ToastContent {
    @Observable
    final class Activity {
        /// nil なら進み具合が分からない処理。
        var progress: Double?
        init(progress: Double?) { self.progress = progress }
    }

    let message: String
    let detail: String?
    let fileURL: URL?
    let activity: Activity?

    init(message: String, detail: String?, fileURL: URL?, activity: Activity?) {
        self.message = message
        self.detail = detail
        self.fileURL = fileURL
        self.activity = activity
    }
}

private struct ToastView: View {
    let content: ToastContent
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if content.activity != nil {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 22, height: 22)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(content.message).font(.headline)
                if let detail = content.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if let progress = content.activity?.progress {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .controlSize(.small)
                        .frame(width: 200)
                }
            }
            if let fileURL = content.fileURL {
                Spacer(minLength: 8)
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                    dismiss()
                }
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minWidth: 240, maxWidth: 420)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
    }
}
