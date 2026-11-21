import SwiftUI

@main
struct PrintScreenApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // メニューバーと設定ウインドウは StatusItemController が管理する
        Settings {
            EmptyView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
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
}
