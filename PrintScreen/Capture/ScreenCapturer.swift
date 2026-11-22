import AppKit
import ScreenCaptureKit

enum ScreenCapturer {
    enum CaptureError: LocalizedError {
        case displayNotFound
        case windowNotFound
        var errorDescription: String? {
            switch self {
            case .displayNotFound: String(localized: "Display not found")
            case .windowNotFound: String(localized: "Window not found")
            }
        }
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

    /// ウインドウ単体を影付き・背景透過で撮影する。
    static func capture(window selection: WindowSelection) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let window = content.windows.first(where: { $0.windowID == selection.windowID }) else {
            throw CaptureError.windowNotFound
        }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        let scale = selection.pixelScale
        // 影の分だけ大きいキャンバスに撮り、あとで透明な余白を切り落とす
        let shadowMargin: CGFloat = 120
        config.width = Int((selection.rect.width + shadowMargin * 2) * scale)
        config.height = Int((selection.rect.height + shadowMargin * 2) * scale)
        config.scalesToFit = false
        config.ignoreShadowsSingleWindow = false
        config.backgroundColor = .clear
        config.showsCursor = false
        config.captureResolution = .best
        config.colorSpaceName = CGColorSpace.sRGB
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        return trimTransparentEdges(image) ?? image
    }

    /// 周囲の完全に透明な行と列を切り落とす。
    private static func trimTransparentEdges(_ image: CGImage) -> CGImage? {
        let width = image.width
        let height = image.height
        var alpha = [UInt8](repeating: 0, count: width * height)
        let drawn = alpha.withUnsafeMutableBytes { buffer -> Bool in
            guard let ctx = CGContext(data: buffer.baseAddress, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        var minX = width, maxX = -1, minY = height, maxY = -1
        for y in 0..<height {
            for x in 0..<width where alpha[y * width + x] != 0 {
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        // ビットマップの行は上から並ぶので、そのまま cropping の座標に使える
        return image.cropping(to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1))
    }
}
