import AppKit
import Observation

// 設定画面の撮影コード。tools/media/media.sh で一時的にアプリへ組み込む。
enum TempShots {
    @Observable final class State { var tab = 0 }
    static let state = State()
    static var root: String { UserDefaults.standard.string(forKey: "TempOut") ?? NSTemporaryDirectory() }

    static func wait(_ s: Double) async { try? await Task.sleep(for: .seconds(s)) }

    static func run(lang: String) {
        Task {
            StatusItemController.shared.openSettings()
            await wait(0.6)
            guard let window = NSApp.windows.first(where: { $0.title == String(localized: "PrintScreen Settings") }) else { exit(1) }
            let dir = URL(fileURLWithPath: "\(root)/\(lang)")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            for (tab, name) in [(0, "general"), (1, "image"), (2, "video"), (3, "shortcuts"), (4, "about")] {
                state.tab = tab
                window.orderFrontRegardless()
                await wait(1)
                do {
                    let selection = WindowSelection(windowID: CGWindowID(window.windowNumber), rect: window.frame)
                    let image = try await ScreenCapturer.capture(window: selection)
                    try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?
                        .write(to: dir.appending(path: "settings-\(name).png"))
                } catch {
                    try? "\(name): \(error)".write(toFile: "\(root)/error-settings-\(lang).txt", atomically: true, encoding: .utf8)
                }
            }
            exit(0)
        }
    }
}
