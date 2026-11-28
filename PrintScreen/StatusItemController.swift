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
        // 非表示の設定でも、録画を止められるように録画中は出す
        item.isVisible = isRecording || AppSettings.shared.showMenuBarIcon
        // menu があるとクリックでメニューが開き、nil だと action が呼ばれる
        item.menu = isRecording ? nil : menu
        let symbol = isRecording ? "stop.circle.fill" : "camera.viewfinder"
        let title = isRecording ? String(localized: "Stop Recording") : "PrintScreen"
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
        addActionItem(String(localized: "Capture Area"), .captureArea)
        addActionItem(String(localized: "Capture Full Screen"), .captureFullScreen)
        addActionItem(String(localized: "Record Area"), .recordArea)
        menu.addItem(.separator())
        addItem(String(localized: "Open Save Folder"), #selector(openSaveDirectory))
        addItem(String(localized: "Settings…"), #selector(openSettings), key: ",")
        menu.addItem(.separator())
        addItem(String(localized: "Quit PrintScreen"), #selector(quit), key: "q")
    }

    private func addActionItem(_ title: String, _ action: HotkeyAction) {
        let item = addItem(title, #selector(performAction(_:)))
        item.representedObject = action.rawValue
        // メニューに出せるのは 1 文字のキーだけなので、最初に見つかったものを出す
        if let combo = HotkeyManager.shared.combos[action]?.first(where: { KeyCombo.keyName(for: $0.keyCode).count == 1 }) {
            item.keyEquivalent = KeyCombo.keyName(for: combo.keyCode).lowercased()
            item.keyEquivalentModifierMask = combo.modifierFlags
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

    @objc func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            window.title = String(localized: "PrintScreen Settings")
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
