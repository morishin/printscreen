import AppKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") { GeneralSettingsView() }
            Tab("Image", systemImage: "photo") { ImageSettingsView() }
            Tab("Video", systemImage: "video") { VideoSettingsView() }
            Tab("Shortcuts", systemImage: "command") { ShortcutSettingsView() }
            Tab("About", systemImage: "info.circle") { AboutView() }
        }
        // Form は高さを主張しないので、指定しないとウインドウが潰れて中身が見えなくなる
        .frame(width: 520, height: 500)
    }
}

private struct GeneralSettingsView: View {
    @Bindable private var settings = AppSettings.shared
    @State private var loginItemStatus = SMAppService.mainApp.status
    @State private var loginItemError: String?

    private var launchAtLoginBinding: Binding<Bool> {
        Binding {
            loginItemStatus == .enabled || loginItemStatus == .requiresApproval
        } set: { enabled in
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
                loginItemError = nil
            } catch {
                loginItemError = error.localizedDescription
            }
            loginItemStatus = SMAppService.mainApp.status
        }
    }

    var body: some View {
        Form {
            Section("Startup & Appearance") {
                Toggle("Launch at Login", isOn: launchAtLoginBinding)
                if loginItemStatus == .requiresApproval {
                    HStack {
                        Text("Allow this login item in System Settings.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Open System Settings") { SMAppService.openSystemSettingsLoginItems() }
                            .controlSize(.small)
                    }
                }
                if let loginItemError {
                    Text(loginItemError)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
                Toggle("Show in Menu Bar", isOn: $settings.showMenuBarIcon)
                if !settings.showMenuBarIcon {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Shortcuts keep working while hidden, and a stop button appears during recording. To open Settings, open the app again from Finder.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Button("Quit PrintScreen") { NSApp.terminate(nil) }
                            .controlSize(.small)
                    }
                }
            }
            Section("Save Location") {
                LabeledContent("Folder") {
                    HStack {
                        Text(settings.saveDirectory.path(percentEncoded: false)
                            .replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Menu("Change") {
                            Button("Desktop") { settings.saveDirectory = Self.directory(.desktopDirectory) }
                            Button("Downloads") { settings.saveDirectory = Self.directory(.downloadsDirectory) }
                            Button("Pictures") { settings.saveDirectory = Self.directory(.picturesDirectory) }
                            Divider()
                            Button("Other…") { chooseFolder() }
                        }
                        .fixedSize()
                    }
                }
                Button("Open in Finder") {
                    NSWorkspace.shared.open(settings.saveDirectory)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { loginItemStatus = SMAppService.mainApp.status }
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
        panel.prompt = String(localized: "Choose")
        NSApp.activate()
        if panel.runModal() == .OK, let url = panel.url {
            settings.saveDirectory = url
        }
    }
}

private struct ImageSettingsView: View {
    @Bindable private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section("Image") {
                Picker("Format", selection: $settings.imageFormat) {
                    ForEach(ImageFormat.allCases) { Text($0.label).tag($0) }
                }
                if settings.imageFormat != .png {
                    LabeledContent("Quality") {
                        HStack {
                            Slider(value: $settings.imageQuality, in: 50...100, step: 5)
                            Text("\(Int(settings.imageQuality))").monospacedDigit().frame(width: 32)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct VideoSettingsView: View {
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
                Picker("Format", selection: videoFormatBinding) {
                    ForEach(VideoFormat.allCases) { format in
                        Text(format == .webm && !ffmpegAvailable ? String(localized: "\(format.label) (requires ffmpeg)") : format.label)
                            .tag(format)
                            .disabled(format == .webm && !ffmpegAvailable)
                    }
                }
                if !ffmpegAvailable {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Saving as WebM requires ffmpeg. Run the following command in Terminal to install it and enable this option. Recordings are saved as MP4 for now.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        HStack {
                            Text("brew install ffmpeg")
                                .font(.callout.monospaced())
                                .textSelection(.enabled)
                            Button("Copy") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString("brew install ffmpeg", forType: .string)
                            }
                            .controlSize(.small)
                            Spacer()
                            Button("Check Again") { ffmpegAvailable = FFmpeg.executableURL != nil }
                                .controlSize(.small)
                        }
                    }
                }
            } header: {
                Text("Video")
            }
            Section("After Recording") {
                Toggle("Show Saved File in Finder", isOn: $settings.revealRecordingInFinder)
            }
            Section("Overlays") {
                Toggle("Show Mouse Clicks", isOn: $settings.showClicks)
                Toggle("Show Pressed Keys", isOn: $settings.showKeystrokes)
                if settings.showKeystrokes && !accessibilityTrusted {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Showing keys requires Accessibility permission.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        HStack {
                            Button("Open System Settings") {
                                KeystrokeMonitor.requestAccessibilityPermission()
                            }
                            Button("Check Again") { accessibilityTrusted = AXIsProcessTrusted() }
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
                                Text("Already in use by another app")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                }
            } footer: {
                Text("To use ⌘⇧3 / ⌘⇧4 / ⌘⇧5, turn off the macOS shortcuts in System Settings › Keyboard › Keyboard Shortcuts › Screenshots.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section {
                Button("Open Keyboard Shortcuts Settings") {
                    // ?Shortcuts でキーボードショートカットのシートまで開く。スクリーンショットの項目は選べない
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension?Shortcuts")!)
                }
            } footer: {
                // 言語ごとの画像は tools/media/system_shortcuts.sh で撮り直す
                Image("SystemScreenshotShortcuts")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
                    .padding(.top, 4)
                    .accessibilityHidden(true)
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
                Text(isRecording ? String(localized: "Press keys…") : (hotkeys.combos[action]?.displayString ?? String(localized: "None")))
                    .frame(minWidth: 140)
            }
            Button {
                hotkeys.setCombo(nil, for: action)
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.borderless)
            .help("Remove Shortcut")
            .disabled(hotkeys.combos[action] == nil)
            Button {
                hotkeys.setCombo(action.defaultCombo, for: action)
            } label: {
                Image(systemName: "arrow.counterclockwise")
            }
            .buttonStyle(.borderless)
            .help("Reset to default (\(action.defaultCombo.displayString))")
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
