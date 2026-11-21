import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Observation
import SwiftUI

enum KeystrokeMonitor {
    /// ほかのアプリでのキー入力を受け取るには、アクセシビリティの許可が要る。
    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(options) {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
    }

    /// キーイベントを表示用の文字列にする。
    static func describe(_ event: NSEvent) -> (text: String, isCombo: Bool) {
        let mods = event.modifierFlags.intersection([.command, .control, .option, .shift])
        let named: [Int: String] = [
            kVK_Return: "↩", kVK_ANSI_KeypadEnter: "⌤", kVK_Tab: "⇥", kVK_Space: "␣", kVK_Delete: "⌫",
            kVK_Escape: "⎋", kVK_ForwardDelete: "⌦", kVK_LeftArrow: "←", kVK_RightArrow: "→",
            kVK_UpArrow: "↑", kVK_DownArrow: "↓", kVK_Home: "↖", kVK_End: "↘",
            kVK_PageUp: "⇞", kVK_PageDown: "⇟",
            kVK_JIS_Eisu: "英数", kVK_JIS_Kana: "かな",
        ]
        let keyName = named[Int(event.keyCode)]
        let hasCommandLike = !mods.intersection([.command, .control, .option]).isEmpty
        if hasCommandLike || (keyName != nil && !mods.isEmpty) {
            var s = ""
            if mods.contains(.control) { s += "⌃" }
            if mods.contains(.option) { s += "⌥" }
            if mods.contains(.shift) { s += "⇧" }
            if mods.contains(.command) { s += "⌘" }
            s += keyName ?? KeyCombo.keyName(for: UInt32(event.keyCode))
            return (s, true)
        }
        if let keyName { return (keyName, true) }
        return (event.characters ?? "", false)
    }
}

@Observable
final class KeystrokeModel {
    struct Chunk: Identifiable {
        let id = UUID()
        var text: String
        let isCombo: Bool
    }
    var chunks: [Chunk] = []
    @ObservationIgnored private var lastInput = Date.distantPast
    @ObservationIgnored private var clearWork: DispatchWorkItem?

    func push(text: String, isCombo: Bool) {
        guard !text.isEmpty else { return }
        let now = Date()
        // 続けて打った普通の文字は 1 つにまとめる
        if !isCombo, let last = chunks.last, !last.isCombo, now.timeIntervalSince(lastInput) < 1.5 {
            chunks[chunks.count - 1].text = String((last.text + text).suffix(24))
        } else {
            chunks.append(Chunk(text: text, isCombo: isCombo))
            if chunks.count > 4 { chunks.removeFirst(chunks.count - 4) }
        }
        lastInput = now
        clearWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            withAnimation(.easeOut(duration: 0.3)) { self?.chunks.removeAll() }
        }
        clearWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }
}

/// 録画範囲の右下に、押したキーを表示する。
final class KeystrokeOverlay {
    private let panel: NSPanel
    private let model = KeystrokeModel()
    private var monitors: [Any] = []

    var windowNumber: Int { panel.windowNumber }

    init(recordingRect: CGRect) {
        let margin: CGFloat = 16
        let width = min(recordingRect.width - margin * 2, 520)
        let height: CGFloat = 56
        let frame = CGRect(x: recordingRect.maxX - margin - width, y: recordingRect.minY + margin,
                           width: max(width, 60), height: height)
        panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = NSHostingView(rootView: KeystrokeView(model: model))
    }

    func start() {
        panel.orderFrontRegardless()
        let handler: (NSEvent) -> Void = { [weak self] event in
            let (text, isCombo) = KeystrokeMonitor.describe(event)
            self?.model.push(text: text, isCombo: isCombo)
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: handler) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { event in
            handler(event)
            return event
        }) {
            monitors.append(local)
        }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        panel.orderOut(nil)
    }
}

private struct KeystrokeView: View {
    let model: KeystrokeModel

    var body: some View {
        HStack(spacing: 6) {
            Spacer(minLength: 0)
            ForEach(model.chunks) { chunk in
                Text(chunk.text)
                    .font(.system(size: 22, weight: .semibold, design: chunk.isCombo ? .rounded : .default))
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .foregroundStyle(.white)
                    .background(.black.opacity(0.72), in: .rect(cornerRadius: 10))
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
    }
}
