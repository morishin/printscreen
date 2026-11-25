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
    private let captureDate: Date

    static func open(image: CGImage, pixelScale: CGFloat, captureDate: Date = .now) {
        let controller = EditorWindowController(image: image, pixelScale: pixelScale, captureDate: captureDate)
        openControllers.insert(controller)
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private init(image: CGImage, pixelScale: CGFloat, captureDate: Date) {
        self.model = EditorModel(image: image, pixelScale: pixelScale)
        self.captureDate = captureDate
        let window = EditorWindow(contentRect: .zero, styleMask: [.titled, .closable, .resizable, .miniaturizable],
                                  backing: .buffered, defer: false)
        window.title = String(localized: "Screenshot") // Mission Control などで使う。タイトルバーには出さない
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

    /// PNG は画像データのまま、ほかの形式は保存形式のファイルとしてコピーする。
    /// 画像データとしての WebP は多くのアプリが読まず PNG で貼られてしまうため。
    private func copy() {
        model.finishTextEditing?()
        guard let image = model.renderedImage() else { return }
        let settings = AppSettings.shared
        guard settings.imageFormat != .png else {
            Clipboard.copy(image)
            Toast.show(String(localized: "Copied to Clipboard"))
            return
        }
        do {
            let data = try ImageEncoder.encode(image, format: settings.imageFormat, quality: settings.imageQuality)
            let name = OutputFiles.baseName(prefix: String(localized: "Screenshot"), date: captureDate)
            let url = try Clipboard.temporaryFileURL(name: name, ext: settings.imageFormat.fileExtension)
            try data.write(to: url)
            Clipboard.copyFile(url)
            Toast.show(String(localized: "Copied to Clipboard"), detail: url.lastPathComponent)
        } catch {
            NSAlert(error: error).beginSheetModal(for: window!)
        }
    }

    private func save() {
        model.finishTextEditing?()
        guard let image = model.renderedImage() else { return }
        let settings = AppSettings.shared
        do {
            let data = try ImageEncoder.encode(image, format: settings.imageFormat, quality: settings.imageQuality)
            try OutputFiles.ensureDirectory(settings.saveDirectory)
            let url = OutputFiles.uniqueURL(directory: settings.saveDirectory,
                                            baseName: OutputFiles.baseName(prefix: String(localized: "Screenshot"), date: captureDate),
                                            ext: settings.imageFormat.fileExtension)
            try data.write(to: url)
            model.isSaved = true
            close()
            Toast.show(String(localized: "Saved"), detail: url.lastPathComponent, fileURL: url)
        } catch {
            let alert = NSAlert(error: error)
            alert.beginSheetModal(for: window!)
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
    static func copy(_ image: CGImage) {
        let rep = NSBitmapImageRep(cgImage: image)
        guard let png = rep.representation(using: .png, properties: [:]) else { return }
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
