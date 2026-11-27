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

    /// 範囲を撮影する。rect はディスプレイ左上原点のポイントで、nil なら画面全体。
    /// ディスプレイを指定する撮り方ではウインドウやメニューの影が写らないので、
    /// macOS 標準のスクリーンショットと同じく影まで写る、画面上の範囲を指定する撮り方を使う。
    static func capture(screen: NSScreen, rect: CGRect?) async throws -> CGImage {
        let display = CGDisplayBounds(displayID(of: screen))
        let local = rect ?? CGRect(origin: .zero, size: display.size)
        let global = local.offsetBy(dx: display.minX, dy: display.minY)
        return try await SCScreenshotManager.captureImage(in: global)
    }

    /// すべての画面をそのまま撮る。範囲選択の前に撮っておき、右クリックメニューやツールチップのように
    /// オーバーレイを出すと消えてしまうものも写るようにする。キーは画面の displayID。
    static func snapshotAllScreens() async -> [CGDirectDisplayID: CGImage] {
        await withTaskGroup(of: (CGDirectDisplayID, CGImage?).self) { group in
            for screen in NSScreen.screens {
                let id = displayID(of: screen)
                group.addTask { @MainActor in (id, try? await capture(screen: screen, rect: nil)) }
            }
            var result: [CGDirectDisplayID: CGImage] = [:]
            for await (id, image) in group {
                if let image { result[id] = image }
            }
            return result
        }
    }

    /// 撮っておいた画面全体の画像から範囲を切り出す。rect はディスプレイ左上原点のポイント。
    static func crop(_ snapshot: CGImage, screen: NSScreen, rect: CGRect) -> CGImage? {
        let scale = CGFloat(snapshot.width) / screen.frame.width
        let pixelRect = CGRect(x: rect.minX * scale, y: rect.minY * scale,
                               width: rect.width * scale, height: rect.height * scale).integral
        return snapshot.cropping(to: pixelRect)
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
