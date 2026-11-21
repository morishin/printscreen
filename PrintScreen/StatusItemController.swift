import AppKit
import SwiftUI

/// メニューバーのアイコン。通常はメニューを開き、録画中は 1 クリックで録画を止める。
final class StatusItemController: NSObject, NSMenuDelegate {
    static let shared = StatusItemController()

    private var statusItem: NSStatusItem?
    private let menu = NSMenu()
    private var settingsWindow: NSWindow?

    func install() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked)
        menu.delegate = self
        statusItem = item
        update(isRecording: false)
    }

    func update(isRecording: Bool) {
        guard let item = statusItem, let button = item.button else { return }
        // menu があるとクリックでメニューが開き、nil だと action が呼ばれる
        item.menu = isRecording ? nil : menu
        let symbol = isRecording ? "stop.circle.fill" : "camera.viewfinder"
        let title = isRecording ? "録画を停止" : "PrintScreen"
        // テンプレート画像にして、メニューバーの文字色（元のアイコンと同じ色）で描かせる
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        image?.isTemplate = true
        button.image = image
        button.contentTintColor = nil
        button.toolTip = title
    }

    @objc private func statusItemClicked() {
        AppController.shared.stopRecording()
    }

    // MARK: NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        addActionItem("範囲を選択して撮影", .captureArea)
        addActionItem("画面全体を撮影", .captureFullScreen)
        addActionItem("範囲を選択して録画", .recordArea)
        menu.addItem(.separator())
        addItem("保存先を開く", #selector(openSaveDirectory))
        addItem("設定…", #selector(openSettings), key: ",")
        menu.addItem(.separator())
        addItem("PrintScreen を終了", #selector(quit), key: "q")
    }

    private func addActionItem(_ title: String, _ action: HotkeyAction) {
        let item = addItem(title, #selector(performAction(_:)))
        item.representedObject = action.rawValue
        if let combo = HotkeyManager.shared.combos[action] {
            let name = KeyCombo.keyName(for: combo.keyCode)
            if name.count == 1 {
                item.keyEquivalent = name.lowercased()
                item.keyEquivalentModifierMask = combo.modifierFlags
            }
        }
    }

    @discardableResult
    private func addItem(_ title: String, _ selector: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
        return item
    }

    @objc private func performAction(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let action = HotkeyAction(rawValue: raw) else { return }
        // メニューが閉じてから範囲選択を始める
        DispatchQueue.main.async { AppController.shared.perform(action) }
    }

    @objc private func openSaveDirectory() {
        NSWorkspace.shared.open(AppSettings.shared.saveDirectory)
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            window.title = "PrintScreen 設定"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
