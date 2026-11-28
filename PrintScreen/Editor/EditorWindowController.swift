import AppKit
import SwiftUI

/// ⌘W を破棄として受け取るウインドウ。
private final class EditorWindow: NSWindow {
    var onCommandW: (() -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        if modifiers == .command, event.charactersIgnoringModifiers?.lowercased() == "w" {
            onCommandW?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

/// 撮影した画像を編集するウインドウ。
final class EditorWindowController: NSWindowController, NSWindowDelegate {
    private static var openControllers: Set<EditorWindowController> = []

    private let model: EditorModel
    /// 保存するファイルの名前（拡張子なし）
    private let baseName: String

    static func open(image: CGImage, pixelScale: CGFloat, captureDate: Date = .now) {
        show(EditorWindowController(image: image, pixelScale: pixelScale,
                                    baseName: OutputFiles.baseName(prefix: String(localized: "Screenshot"), date: captureDate),
                                    title: String(localized: "Screenshot")))
    }

    /// 既存の画像ファイルを開いて書き込む。保存は元のファイルを上書きせず、保存先フォルダに同じ名前で書き出す。
    static func open(fileURL: URL) {
        guard let loaded = ImageFile.load(fileURL) else {
            let alert = NSAlert()
            alert.messageText = String(localized: "Can't open the image")
            alert.informativeText = fileURL.lastPathComponent
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
            return
        }
        let controller = EditorWindowController(image: loaded.image, pixelScale: loaded.pixelScale,
                                                baseName: fileURL.deletingPathExtension().lastPathComponent,
                                                title: fileURL.lastPathComponent)
        if let format = loaded.format { controller.model.format = format }
        show(controller)
    }

    private static func show(_ controller: EditorWindowController) {
        openControllers.insert(controller)
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private init(image: CGImage, pixelScale: CGFloat, baseName: String, title: String) {
        self.model = EditorModel(image: image, pixelScale: pixelScale)
        self.baseName = baseName
        let window = EditorWindow(contentRect: .zero, styleMask: [.titled, .closable, .resizable, .miniaturizable],
                                  backing: .buffered, defer: false)
        window.title = title // Mission Control などで使う。タイトルバーには出さない
        window.titleVisibility = .hidden
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        super.init(window: window)
        window.delegate = self
        window.onCommandW = { [weak self] in self?.requestDiscard() }

        let view = EditorView(model: model,
                              onCopy: { [weak self] in self?.copy() },
                              onSave: { [weak self] in self?.save() },
                              onDiscard: { [weak self] in self?.requestDiscard() })
        window.contentViewController = NSHostingController(rootView: view)
        window.setContentSize(initialContentSize(for: image, pixelScale: pixelScale))
        window.center()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func initialContentSize(for image: CGImage, pixelScale: CGFloat) -> CGSize {
        let pointSize = CGSize(width: CGFloat(image.width) / pixelScale, height: CGFloat(image.height) / pixelScale)
        let visible = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame.size
        let maxSize = CGSize(width: visible.width * 0.85, height: visible.height * 0.85 - 60)
        let scale = min(1, maxSize.width / (pointSize.width + 24), maxSize.height / (pointSize.height + 24))
        return CGSize(width: max(EditorView.minimumWidth, pointSize.width * scale + 24),
                      height: max(320, pointSize.height * scale + 24))
    }

    // MARK: 操作

    /// 書き出し中。コピーや保存を重ねて始めないようにする。
    private var isExporting = false

    /// 書き出しの間に出すトーストの文言。
    private static func exportingMessage(_ format: ImageFormat) -> String {
        String(localized: "Converting to \(format.label)…")
    }

    /// 画像を作ってから、形式の変換をバックグラウンドで行う。WebP などは 1 秒ほどかかるので、その間はトーストを出しておく。
    /// 書き込みがなければ、書き出したらウインドウを閉じる。変換を待たずに先に隠し、失敗したら出し直す。
    /// 書き込みがあるときは、続けて直したくなることがあるので閉じない。
    private func export(then completion: @escaping (CGImage, Data) throws -> Void) {
        guard !isExporting else { return }
        model.finishTextEditing?()
        let format = model.format
        let quality = AppSettings.shared.imageQuality
        let closesWindow = model.annotations.isEmpty
        if closesWindow { window?.orderOut(nil) }
        Toast.showActivity(Self.exportingMessage(format))
        guard let image = model.renderedImage() else {
            Toast.hide()
            if closesWindow { window?.makeKeyAndOrderFront(nil) }
            return
        }
        isExporting = true
        Task {
            defer { isExporting = false }
            do {
                let data = try await Task.detached(priority: .userInitiated) {
                    try ImageEncoder.encode(image, format: format, quality: quality)
                }.value
                try completion(image, data)
                if closesWindow { discard() }
            } catch {
                showExportError(error)
            }
        }
    }

    /// 書き出しに失敗したとき。隠したウインドウを出し直して知らせる。
    private func showExportError(_ error: Error) {
        Toast.hide()
        guard let window else { return }
        if !window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
        NSAlert(error: error).beginSheetModal(for: window)
    }

    /// PNG は画像データのまま、ほかの形式は保存形式のファイルとしてコピーする。
    /// 画像データとしての WebP は多くのアプリが読まず PNG で貼られてしまうため。
    private func copy() {
        let format = model.format
        let name = baseName
        export { image, data in
            if format == .png {
                Clipboard.copy(image, png: data)
                Toast.show(String(localized: "Copied to Clipboard"))
            } else {
                let url = try Clipboard.temporaryFileURL(name: name, ext: format.fileExtension)
                try data.write(to: url)
                Clipboard.copyFile(url)
                Toast.show(String(localized: "Copied to Clipboard"), detail: url.lastPathComponent)
            }
        }
    }

    private func save() {
        let format = model.format
        let name = baseName
        export { [weak self] _, data in
            let settings = AppSettings.shared
            try OutputFiles.ensureDirectory(settings.saveDirectory)
            let url = OutputFiles.uniqueURL(directory: settings.saveDirectory, baseName: name,
                                            ext: format.fileExtension)
            try data.write(to: url)
            self?.model.isSaved = true
            Toast.show(String(localized: "Saved"), detail: url.lastPathComponent, fileURL: url)
        }
    }

    private func discard() {
        model.isSaved = true // 確認なしで閉じる
        close()
    }

    /// ⌘W と破棄ボタン。書き込みがあるときは誤操作で失わないよう確認する。
    private func requestDiscard() {
        model.finishTextEditing?()
        if model.annotations.isEmpty {
            discard()
        } else {
            window?.performClose(nil)
        }
    }

    override func cancelOperation(_ sender: Any?) {
        model.handleEscape()
    }

    // MARK: NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if model.isSaved { return true }
        let alert = NSAlert()
        alert.messageText = String(localized: "Close without saving?")
        alert.informativeText = String(localized: "The captured image won't be saved.")
        alert.addButton(withTitle: String(localized: "Save"))
        alert.addButton(withTitle: String(localized: "Don't Save"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.buttons[1].hasDestructiveAction = true
        alert.beginSheetModal(for: sender) { [weak self] response in
            switch response {
            case .alertFirstButtonReturn: self?.save()
            case .alertSecondButtonReturn: self?.discard()
            default: break
            }
        }
        return false
    }

    func windowWillClose(_ notification: Notification) {
        EditorWindowController.openControllers.remove(self)
    }
}

enum Clipboard {
    static func copy(_ image: CGImage, png: Data) {
        let rep = NSBitmapImageRep(cgImage: image)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(png, forType: .png)
        if let tiff = rep.tiffRepresentation { pb.setData(tiff, forType: .tiff) }
    }

    /// コピー用の一時ファイルの場所。貼り付け先が後から読めるよう、次のコピーまで残す。
    static func temporaryFileURL(name: String, ext: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: "Clipboard", directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "\(name).\(ext)")
    }

    static func copyFile(_ url: URL) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([url as NSURL])
    }
}
