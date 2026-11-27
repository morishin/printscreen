import AppKit
import AVFoundation
import os
import ScreenCaptureKit

private let recorderLog = Logger(subsystem: "com.morishin.PrintScreen", category: "Recorder")

/// 選んだ範囲を ScreenCaptureKit で動画ファイルに録画する。
final class ScreenRecorder: NSObject, SCRecordingOutputDelegate, SCStreamDelegate, SCStreamOutput {
    /// 最後にフレームが届いた時刻。フレームのキューから書き込む。
    private nonisolated let lastFrameDate = OSAllocatedUnfairLock<Date?>(initialState: nil)
    private let frameQueue = DispatchQueue(label: "com.morishin.PrintScreen.frames")
    private var watchdog: Task<Void, Never>?
    private var stream: SCStream?
    private var recordingOutput: SCRecordingOutput?
    private var frameWindow: RecordingFrameWindow?
    private var keystrokeOverlay: KeystrokeOverlay?
    private var clickOverlay: ClickRippleOverlay?
    private var finishContinuation: CheckedContinuation<Void, Error>?
    private var didFinishRecording = false
    private var stoppedBySystem = false
    private(set) var outputURL: URL?
    var onUnexpectedStop: ((Error) -> Void)?
    /// macOS のメニューバーの録画インジケータから止められたとき。
    var onUserStopped: (() -> Void)?

    func start(selection: AreaSelection, showClicks: Bool, showKeystrokes: Bool) async throws {
        let screen = selection.screen

        // 録画範囲の枠（録画には映さない）
        let frameWindow = RecordingFrameWindow(rect: selection.rect)
        frameWindow.orderFrontRegardless()
        self.frameWindow = frameWindow

        // 押したキーの表示（録画に映す）
        if showKeystrokes {
            if KeystrokeMonitor.isTrusted {
                let overlay = KeystrokeOverlay(recordingRect: selection.rect)
                overlay.start()
                keystrokeOverlay = overlay
            } else {
                KeystrokeMonitor.requestAccessibilityPermission()
            }
        }

        // クリックの波紋（録画に映す）
        if showClicks {
            let overlay = ClickRippleOverlay(recordingRect: selection.rect)
            overlay.start()
            clickOverlay = overlay
        }

        let (display, _) = try await ScreenCapturer.scDisplay(for: screen)
        // 枠ウインドウを含めた最新のウインドウ一覧を取り直す
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let pid = ProcessInfo.processInfo.processIdentifier
        let visibleInRecording = Set([keystrokeOverlay?.windowNumber, clickOverlay?.windowNumber].compactMap { $0 })
        let excluded = content.windows.filter {
            $0.owningApplication?.processID == pid && !visibleInRecording.contains(Int($0.windowID))
        }
        let filter = SCContentFilter(display: display, excludingWindows: excluded)

        let scale = screen.backingScaleFactor
        let config = SCStreamConfiguration()
        config.sourceRect = selection.displayLocalRect
        // HEVC は偶数のサイズが必要
        config.width = Int(selection.rect.width * scale) / 2 * 2
        config.height = Int(selection.rect.height * scale) / 2 * 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.showsCursor = true
        // 標準の丸表示は使わず、ClickRippleOverlay の波紋を映す
        config.showMouseClicks = false
        config.captureResolution = .best
        config.colorSpaceName = CGColorSpace.sRGB
        config.queueDepth = 6

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PrintScreen-\(UUID().uuidString)")
            .appendingPathExtension("mp4")
        let outputConfig = SCRecordingOutputConfiguration()
        outputConfig.outputURL = url
        outputConfig.outputFileType = .mp4
        outputConfig.videoCodecType = .hevc
        let output = SCRecordingOutput(configuration: outputConfig, delegate: self)

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: frameQueue)
        try stream.addRecordingOutput(output)
        do {
            try await stream.startCapture()
        } catch {
            cleanUpWindows()
            throw error
        }
        self.stream = stream
        self.recordingOutput = output
        self.outputURL = url
        startWatchdog()
    }

    /// macOS 側の停止ボタンで止められると通知が来ないことがあるので、フレームの途絶でも検知する。
    private func startWatchdog() {
        lastFrameDate.withLock { $0 = Date() }
        watchdog = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, self.stream != nil else { return }
                let last = self.lastFrameDate.withLock { $0 } ?? Date()
                if Date().timeIntervalSince(last) > 3 {
                    self.handleSystemStop(reason: "no frames for 3s")
                    return
                }
            }
        }
    }

    /// 自分で止めたのではないのに録画が終わったとき。通常の停止と同じく保存へ進める。
    private func handleSystemStop(reason: String) {
        guard stream != nil, finishContinuation == nil, !stoppedBySystem else { return }
        recorderLog.notice("recording stopped by system: \(reason, privacy: .public)")
        stoppedBySystem = true
        cleanUpWindows()
        onUserStopped?()
    }

    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                            of type: SCStreamOutputType) {
        lastFrameDate.withLock { $0 = Date() }
    }

    /// 録画を止めて、書き出し終わった一時ファイルの URL を返す。
    func stop() async throws -> URL {
        defer { cleanUpWindows() }
        guard let stream, let outputURL else { throw CancellationError() }
        self.stream = nil
        if didFinishRecording { return outputURL }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            finishContinuation = cont
            if stoppedBySystem {
                // 止まっていない場合に備えて止め直し、書き出しの完了を待つ。通知が来なくても固まらないようにする。
                Task {
                    try? await stream.stopCapture()
                    try? await Task.sleep(for: .seconds(3))
                    self.resumeFinish(with: nil)
                }
            } else {
                Task {
                    do {
                        try await stream.stopCapture()
                    } catch {
                        self.resumeFinish(with: error)
                    }
                }
            }
        }
        return outputURL
    }

    private func resumeFinish(with error: Error?) {
        guard let cont = finishContinuation else { return }
        finishContinuation = nil
        if let error { cont.resume(throwing: error) } else { cont.resume() }
    }

    private func cleanUpWindows() {
        watchdog?.cancel()
        watchdog = nil
        frameWindow?.orderOut(nil)
        frameWindow = nil
        keystrokeOverlay?.stop()
        keystrokeOverlay = nil
        clickOverlay?.stop()
        clickOverlay = nil
    }

    // MARK: SCRecordingOutputDelegate

    nonisolated func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        Task { @MainActor in
            self.didFinishRecording = true
            if self.finishContinuation != nil {
                self.resumeFinish(with: nil)
            } else {
                self.handleSystemStop(reason: "recording output finished")
            }
        }
    }

    nonisolated func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        Task { @MainActor in
            if self.finishContinuation != nil {
                self.resumeFinish(with: error)
            } else {
                // 押したキーやクリックの監視を残さないよう、オーバーレイを片付けてから知らせる
                self.cleanUpWindows()
                self.onUnexpectedStop?(error)
            }
        }
    }

    // MARK: SCStreamDelegate

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        let isUserStop = (error as NSError).domain == SCStreamErrorDomain
            && (error as NSError).code == SCStreamError.Code.userStopped.rawValue
        Task { @MainActor in
            if isUserStop {
                // ユーザーの停止操作なので、エラーにせず通常どおり保存する
                self.handleSystemStop(reason: "stream stopped by user")
                return
            }
            self.cleanUpWindows()
            if self.finishContinuation != nil {
                self.resumeFinish(with: error)
            } else {
                self.onUnexpectedStop?(error)
            }
        }
    }
}

/// 録画範囲を示す枠。マウス操作は素通しする。
final class RecordingFrameWindow: NSPanel {
    init(rect: CGRect) {
        let inset: CGFloat = 4
        super.init(contentRect: rect.insetBy(dx: -inset, dy: -inset), styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        sharingType = .none
        contentView = FrameView(inset: inset)
    }

    private final class FrameView: NSView {
        let inset: CGFloat
        init(inset: CGFloat) {
            self.inset = inset
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { fatalError() }

        override func draw(_ dirtyRect: NSRect) {
            let path = NSBezierPath(rect: bounds.insetBy(dx: inset / 2, dy: inset / 2))
            path.lineWidth = 2
            NSColor.systemRed.withAlphaComponent(0.9).setStroke()
            path.setLineDash([6, 4], count: 2, phase: 0)
            path.stroke()
        }
    }
}
