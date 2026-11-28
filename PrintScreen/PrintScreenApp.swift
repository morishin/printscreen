import SwiftUI

@main
struct PrintScreenApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // メニューバーと設定ウインドウは StatusItemController が管理する
        Settings {
            EmptyView()
        }
        .commands {
            // 標準の「設定…」(⌘,) は空の Settings シーンを開いてしまうので、自前の設定ウインドウに差し替える
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { StatusItemController.shared.openSettings() }
                    .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 以前から使っているかを、メニューバーのアイコンなどが設定を書き込む前に判定させる
        _ = HotkeyManager.shared
        // 古いインスタンスが残るとアイコンが増え、ショートカットも奪われるので終了させる
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .filter { $0 != NSRunningApplication.current }
        others.forEach { $0.forceTerminate() }
        // 古いインスタンスがショートカットを手放すのを待ってから登録する
        let delay: TimeInterval = others.isEmpty ? 0 : 0.5
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            AppController.shared.start()
        }
    }

    /// Finder の「このアプリケーションで開く」などで画像を渡されたら、編集画面で開く。
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { EditorWindowController.open(fileURL: url) }
    }

    /// 起動中にアプリをもう一度開いたら設定を出す。アイコンを隠しているときの入口になる。
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        StatusItemController.shared.openSettings()
        return false
    }
}
