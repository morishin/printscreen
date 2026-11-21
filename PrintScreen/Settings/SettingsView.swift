import AppKit
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("一般", systemImage: "gearshape") { GeneralSettingsView() }
            Tab("録画", systemImage: "record.circle") { RecordingSettingsView() }
            Tab("ショートカット", systemImage: "command") { ShortcutSettingsView() }
        }
        // Form は高さを主張しないので、指定しないとウインドウが潰れて中身が見えなくなる
        .frame(width: 520, height: 500)
    }
}

private struct GeneralSettingsView: View {
    @Bindable private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section("保存先") {
                LabeledContent("フォルダ") {
                    HStack {
                        Text(settings.saveDirectory.path(percentEncoded: false)
                            .replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Menu("変更") {
                            Button("デスクトップ") { settings.saveDirectory = Self.directory(.desktopDirectory) }
                            Button("ダウンロード") { settings.saveDirectory = Self.directory(.downloadsDirectory) }
                            Button("ピクチャ") { settings.saveDirectory = Self.directory(.picturesDirectory) }
                            Divider()
                            Button("その他…") { chooseFolder() }
                        }
                        .fixedSize()
                    }
                }
                Button("Finder で開く") {
                    NSWorkspace.shared.open(settings.saveDirectory)
                }
            }
            Section("画像") {
                Picker("形式", selection: $settings.imageFormat) {
                    ForEach(ImageFormat.allCases) { Text($0.label).tag($0) }
                }
                if settings.imageFormat != .png {
                    LabeledContent("品質") {
                        HStack {
                            Slider(value: $settings.imageQuality, in: 50...100, step: 5)
                            Text("\(Int(settings.imageQuality))").monospacedDigit().frame(width: 32)
                        }
                    }
                }
                Toggle("保存時にクリップボードにもコピーする", isOn: $settings.copyToClipboardOnSave)
            }
        }
        .formStyle(.grouped)
    }

    private static func directory(_ d: FileManager.SearchPathDirectory) -> URL {
        FileManager.default.urls(for: d, in: .userDomainMask).first!
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = settings.saveDirectory
        panel.prompt = "選択"
        NSApp.activate()
        if panel.runModal() == .OK, let url = panel.url {
            settings.saveDirectory = url
        }
    }
}

private struct RecordingSettingsView: View {
    @Bindable private var settings = AppSettings.shared
    @State private var ffmpegAvailable = FFmpeg.executableURL != nil
    @State private var accessibilityTrusted = AXIsProcessTrusted()

    /// ffmpeg が無いときは WebM を選べないようにし、表示は実際に使う形式（MP4）にする。
    private var videoFormatBinding: Binding<VideoFormat> {
        Binding {
            ffmpegAvailable ? settings.videoFormat : settings.effectiveVideoFormat
        } set: { newValue in
            guard newValue != .webm || ffmpegAvailable else { return }
            settings.videoFormat = newValue
        }
    }

    var body: some View {
        Form {
            Section {
                Picker("形式", selection: videoFormatBinding) {
                    ForEach(VideoFormat.allCases) { format in
                        Text(format == .webm && !ffmpegAvailable ? "\(format.label)（ffmpeg が必要）" : format.label)
                            .tag(format)
                            .disabled(format == .webm && !ffmpegAvailable)
                    }
                }
                if !ffmpegAvailable {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("WebM で保存するには ffmpeg が必要です。ターミナルで次のコマンドを実行してインストールすると選べるようになります。いまは MP4 で保存します。")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        HStack {
                            Text("brew install ffmpeg")
                                .font(.callout.monospaced())
                                .textSelection(.enabled)
                            Button("コピー") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString("brew install ffmpeg", forType: .string)
                            }
                            .controlSize(.small)
                            Spacer()
                            Button("再確認") { ffmpegAvailable = FFmpeg.executableURL != nil }
                                .controlSize(.small)
                        }
                    }
                }
            } header: {
                Text("動画")
            }
            Section("録画の終了後") {
                Toggle("保存したファイルを Finder で表示する", isOn: $settings.revealRecordingInFinder)
            }
            Section("表示") {
                Toggle("マウスのクリックを表示する", isOn: $settings.showClicks)
                Toggle("押したキーを表示する", isOn: $settings.showKeystrokes)
                if settings.showKeystrokes && !accessibilityTrusted {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("キーを表示するには「アクセシビリティ」の許可が必要です。")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        HStack {
                            Button("システム設定を開く") {
                                KeystrokeMonitor.requestAccessibilityPermission()
                            }
                            Button("再確認") { accessibilityTrusted = AXIsProcessTrusted() }
                        }
                        .controlSize(.small)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            ffmpegAvailable = FFmpeg.executableURL != nil
            accessibilityTrusted = AXIsProcessTrusted()
        }
    }
}

private struct ShortcutSettingsView: View {
    private var hotkeys = HotkeyManager.shared

    var body: some View {
        Form {
            Section {
                ForEach(HotkeyAction.allCases) { action in
                    LabeledContent(action.title) {
                        VStack(alignment: .trailing, spacing: 2) {
                            ShortcutRecorder(action: action)
                            if hotkeys.failedActions.contains(action) {
                                Text("ほかで使われていて登録できません")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                }
            } footer: {
                Text("⌘⇧3 / ⌘⇧4 / ⌘⇧5 を使うには、システム設定 › キーボード › キーボードショートカット › スクリーンショット で macOS 標準のショートカットをオフにしてください。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Button("キーボードショートカットの設定を開く") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!)
            }
        }
        .formStyle(.grouped)
    }
}

/// クリックしてからキーを押すとショートカットを記録するボタン。
private struct ShortcutRecorder: View {
    let action: HotkeyAction
    @State private var isRecording = false
    @State private var monitor: Any?
    private var hotkeys = HotkeyManager.shared

    init(action: HotkeyAction) {
        self.action = action
    }

    var body: some View {
        HStack(spacing: 4) {
            Button {
                isRecording ? stopRecording() : startRecording()
            } label: {
                Text(isRecording ? "キーを押してください…" : (hotkeys.combos[action]?.displayString ?? "なし"))
                    .frame(minWidth: 140)
            }
            Button {
                hotkeys.setCombo(nil, for: action)
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.borderless)
            .help("ショートカットを外す")
            .disabled(hotkeys.combos[action] == nil)
            Button {
                hotkeys.setCombo(action.defaultCombo, for: action)
            } label: {
                Image(systemName: "arrow.counterclockwise")
            }
            .buttonStyle(.borderless)
            .help("初期値（\(action.defaultCombo.displayString)）に戻す")
        }
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        isRecording = true
        hotkeys.suspend()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let mods = event.modifierFlags.intersection(KeyCombo.relevantModifiers)
            if event.keyCode == 53 && mods.isEmpty { // Esc でキャンセル
                stopRecording()
                return nil
            }
            // 修飾キーなしは誤爆しやすいので受け付けない（ファンクションキーは除く）
            let isFunctionKey = (122...135).contains(Int(event.keyCode)) || [96, 97, 98, 99, 100, 101, 103, 105, 106, 107, 109, 111, 113, 118, 120].contains(Int(event.keyCode))
            guard !mods.isEmpty || isFunctionKey else { return nil }
            stopRecording()
            hotkeys.setCombo(KeyCombo(keyCode: UInt32(event.keyCode), modifiers: mods.rawValue), for: action)
            return nil
        }
    }

    private func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        hotkeys.resume()
    }
}
