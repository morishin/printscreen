import AppKit
import Observation

/// 撮影・録画の流れをまとめる。
@Observable
final class AppController {
    static let shared = AppController()

    private(set) var isRecording = false {
        didSet {
            StatusItemController.shared.update(isRecording: isRecording)
            HotkeyManager.shared.setEscapeEnabled(isRecording)
        }
    }
    @ObservationIgnored private var isBusy = false
    @ObservationIgnored private var recorder: ScreenRecorder?

    private init() {}

    func start() {
        StatusItemController.shared.install()
        HotkeyManager.shared.handler = { [weak self] action in self?.perform(action) }
        HotkeyManager.shared.escapeHandler = { [weak self] in self?.cancelRecording() }
        HotkeyManager.shared.start()
    }

    func perform(_ action: HotkeyAction) {
        if action == .recordArea && isRecording {
            stopRecording()
            return
        }
        guard !isBusy, !isRecording else { return }
        guard ensureScreenCapturePermission() else { return }
        isBusy = true
        Task {
            defer { isBusy = false }
            switch action {
            case .captureFullScreen: await captureFullScreen()
            case .captureArea: await captureArea()
            case .recordArea: await startRecording()
            }
        }
    }

    // MARK: 静止画

    private func captureArea() async {
        // オーバーレイを出す前の画面を撮っておき、選択中はそれを表示して、選んだ範囲を切り出す
        let snapshots = await ScreenCapturer.snapshotAllScreens()
        switch await AreaSelector.selectCaptureTarget(snapshots: snapshots) {
        case .area(let selection):
            let id = ScreenCapturer.displayID(of: selection.screen)
            if let snapshot = snapshots[id],
               let image = ScreenCapturer.crop(snapshot, screen: selection.screen, rect: selection.displayLocalRect) {
                NSSound(named: "Grab")?.play()
                EditorWindowController.open(image: image, pixelScale: selection.screen.backingScaleFactor)
            } else {
                await capture(screen: selection.screen, rect: selection.displayLocalRect)
            }
        case .window(let selection):
            await captureWindow(selection)
        case nil:
            break
        }
    }

    private func captureWindow(_ selection: WindowSelection) async {
        do {
            let date = Date()
            let image = try await ScreenCapturer.capture(window: selection)
            NSSound(named: "Grab")?.play()
            EditorWindowController.open(image: image, pixelScale: selection.pixelScale, captureDate: date)
        } catch {
            showError(error)
        }
    }

    private func captureFullScreen() async {
        await capture(screen: ScreenCapturer.screenUnderMouse, rect: nil)
    }

    private func capture(screen: NSScreen, rect: CGRect?) async {
        do {
            let date = Date()
            let image = try await ScreenCapturer.capture(screen: screen, rect: rect)
            NSSound(named: "Grab")?.play()
            EditorWindowController.open(image: image, pixelScale: screen.backingScaleFactor, captureDate: date)
        } catch {
            showError(error)
        }
    }

    // MARK: 録画

    private func startRecording() async {
        guard let selection = await AreaSelector.select() else { return }
        let settings = AppSettings.shared
        let recorder = ScreenRecorder()
        recorder.onUnexpectedStop = { [weak self] error in
            self?.isRecording = false
            self?.recorder = nil
            self?.showError(error)
        }
        recorder.onUserStopped = { [weak self] in self?.stopRecording() }
        do {
            try await recorder.start(selection: selection, showClicks: settings.showClicks,
                                     showKeystrokes: settings.showKeystrokes)
            self.recorder = recorder
            isRecording = true
            recordingStartDate = Date()
        } catch {
            showError(error)
        }
    }

    @ObservationIgnored private var recordingStartDate = Date()

    func stopRecording() {
        guard let recorder else { return }
        self.recorder = nil
        isRecording = false
        let date = recordingStartDate
        Task {
            do {
                let tempURL = try await recorder.stop()
                try await saveRecording(tempURL, date: date)
            } catch {
                showError(error)
            }
        }
    }

    /// 録画を止めて、保存せずに捨てる。
    func cancelRecording() {
        guard let recorder else { return }
        self.recorder = nil
        isRecording = false
        Task {
            _ = try? await recorder.stop()
            if let url = recorder.outputURL {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    private func saveRecording(_ tempURL: URL, date: Date) async throws {
        let settings = AppSettings.shared
        let format = settings.effectiveVideoFormat
        try OutputFiles.ensureDirectory(settings.saveDirectory)
        let dest = OutputFiles.uniqueURL(directory: settings.saveDirectory,
                                         baseName: OutputFiles.baseName(prefix: String(localized: "Screen Recording"), date: date),
                                         ext: format.fileExtension)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        switch format {
        case .webm:
            Toast.showActivity(String(localized: "Converting to WebM…"), progress: 0)
            try await FFmpeg.convertToWebM(input: tempURL, output: dest) { Toast.setProgress($0) }
        case .mp4:
            try FileManager.default.moveItem(at: tempURL, to: dest)
        case .mov:
            try await remux(tempURL, to: dest, fileType: .mov)
        }
        if settings.revealRecordingInFinder {
            Toast.hide()
            NSWorkspace.shared.activateFileViewerSelecting([dest])
        } else {
            Toast.show(String(localized: "Saved"), detail: dest.lastPathComponent, fileURL: dest)
        }
    }

    /// 再エンコードせずにコンテナだけ入れ替える。
    private func remux(_ source: URL, to dest: URL, fileType: AVFileType) async throws {
        let asset = AVURLAsset(url: source)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try await session.export(to: dest, as: fileType)
    }

    // MARK: 権限とエラー

    private func ensureScreenCapturePermission() -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        CGRequestScreenCaptureAccess()
        let alert = NSAlert()
        alert.messageText = String(localized: "Screen Recording Permission Required")
        alert.informativeText = String(localized: "Allow PrintScreen in System Settings › Privacy & Security › Screen & System Audio Recording. You may need to restart the app afterward.")
        alert.addButton(withTitle: String(localized: "Open System Settings"))
        alert.addButton(withTitle: String(localized: "Close"))
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
        }
        return false
    }

    private func showError(_ error: Error) {
        Toast.hide()
        let alert = NSAlert(error: error)
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

import AVFoundation
