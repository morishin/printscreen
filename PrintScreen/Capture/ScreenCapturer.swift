import AppKit
import ScreenCaptureKit

enum ScreenCapturer {
    enum CaptureError: LocalizedError {
        case displayNotFound
        var errorDescription: String? { "撮影するディスプレイが見つかりません" }
    }

    static func displayID(of screen: NSScreen) -> CGDirectDisplayID {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? CGMainDisplayID()
    }

    static func scDisplay(for screen: NSScreen) async throws -> (SCDisplay, SCShareableContent) {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let id = displayID(of: screen)
        guard let display = content.displays.first(where: { $0.displayID == id }) else {
            throw CaptureError.displayNotFound
        }
        return (display, content)
    }

    /// マウスカーソルがある画面。
    static var screenUnderMouse: NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    /// 範囲を撮影する。selection が nil なら画面全体。
    static func capture(screen: NSScreen, rect: CGRect?) async throws -> CGImage {
        let (display, _) = try await scDisplay(for: screen)
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        let scale = screen.backingScaleFactor
        let sourceRect = rect ?? CGRect(origin: .zero, size: screen.frame.size)
        config.sourceRect = sourceRect
        config.width = Int(sourceRect.width * scale)
        config.height = Int(sourceRect.height * scale)
        config.showsCursor = false
        config.captureResolution = .best
        config.colorSpaceName = CGColorSpace.sRGB
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }
}
