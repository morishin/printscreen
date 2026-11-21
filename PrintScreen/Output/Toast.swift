import AppKit
import SwiftUI

/// 画面右下に短い通知を出す。ファイルがあればクリックで Finder に表示する。
enum Toast {
    private static var panel: NSPanel?
    private static var hideWork: DispatchWorkItem?

    static func show(_ message: String, detail: String? = nil, fileURL: URL? = nil, duration: TimeInterval = 4) {
        hideWork?.cancel()
        panel?.orderOut(nil)

        let view = ToastView(message: message, detail: detail, fileURL: fileURL) { hide() }
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
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let frame = screen.visibleFrame
        panel.setFrameOrigin(CGPoint(x: frame.maxX - size.width - 16, y: frame.minY + 16))
        panel.orderFrontRegardless()
        self.panel = panel

        let work = DispatchWorkItem { hide() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    static func hide() {
        hideWork?.cancel()
        panel?.orderOut(nil)
        panel = nil
    }
}

private struct ToastView: View {
    let message: String
    let detail: String?
    let fileURL: URL?
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text(message).font(.headline)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            if let fileURL {
                Spacer(minLength: 8)
                Button("Finder で表示") {
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
