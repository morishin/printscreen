import AppKit
import ScreenCaptureKit

// サイト用のオーバーレイ画像の撮影コード。tools/media/media.sh で一時的にアプリへ組み込む。
enum TempShots {
    static var root: String { UserDefaults.standard.string(forKey: "TempOut") ?? NSTemporaryDirectory() }

    static func color(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat(hex >> 16 & 255) / 255, green: CGFloat(hex >> 8 & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
    }

    /// 録画範囲に映すフォーム。640 x 340 pt。
    static func form(lang: String) -> CGImage {
        let ja = lang == "ja"
        let (w, h): (CGFloat, CGFloat) = (640, 340)
        let ctx = CGContext(data: nil, width: Int(w * 2), height: Int(h * 2), bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.scaleBy(x: 2, y: 2)
        ctx.translateBy(x: 0, y: h)
        ctx.scaleBy(x: 1, y: -1)
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        color(0xFFFFFF).setFill()
        CGRect(x: 0, y: 0, width: w, height: h).fill()
        func text(_ s: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat, _ hex: UInt32, _ weight: NSFont.Weight = .regular, center: Bool = false) {
            let a = NSAttributedString(string: s, attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color(hex)])
            a.draw(at: CGPoint(x: center ? w / 2 - a.size().width / 2 : x, y: y))
        }
        let fx: CGFloat = 70, fw: CGFloat = 500
        text(ja ? "パスワード" : "Password", fx, 42, 14, 0x3F4653, .semibold)
        let field = CGRect(x: fx, y: 68, width: fw, height: 44)
        color(0xF6F7F9).setFill()
        NSBezierPath(roundedRect: field, xRadius: 8, yRadius: 8).fill()
        color(0xD8DBE2).setStroke()
        NSBezierPath(roundedRect: field.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8).stroke()
        text("••••••••••", fx + 14, 79, 16, 0x1F2430)
        color(0x2F6FED).setFill()
        NSBezierPath(roundedRect: CGRect(x: fx, y: 150, width: fw, height: 52), xRadius: 9, yRadius: 9).fill()
        text(ja ? "アカウントを作成" : "Create account", 0, 165, 17, 0xFFFFFF, .semibold, center: true)
        text(ja ? "すでにアカウントをお持ちの方はログイン" : "Already have an account? Sign in", 0, 228, 14, 0x6B7280, center: true)
        NSGraphicsContext.current = nil
        return ctx.makeImage()!
    }

    static func run(lang: String) {
        Task {
            do { try await shoot(lang) } catch {
                try? "\(error)".write(toFile: "\(root)/error-overlay-\(lang).txt", atomically: true, encoding: .utf8)
            }
            exit(0)
        }
    }

    static func shoot(_ lang: String) async throws {
        guard let screen = NSScreen.main else { return }
        let size = CGSize(width: 640, height: 340)
        let v = screen.visibleFrame
        let rect = CGRect(x: (v.midX - size.width / 2).rounded(), y: (v.midY - size.height / 2).rounded(), width: size.width, height: size.height)
        let window = NSWindow(contentRect: rect, styleMask: .borderless, backing: .buffered, defer: false)
        window.level = .floating
        window.isReleasedWhenClosed = false
        let imageView = NSImageView(image: NSImage(cgImage: form(lang: lang), size: size))
        imageView.imageScaling = .scaleAxesIndependently
        window.contentView = imageView
        window.orderFrontRegardless()
        let ripple = ClickRippleOverlay(recordingRect: rect)
        let keys = KeystrokeOverlay(recordingRect: rect)
        ripple.start()
        keys.start()
        try? await Task.sleep(for: .seconds(0.4))
        keys.model.push(text: "⌘K", isCombo: true)
        keys.model.push(text: "hello", isCombo: false)
        try? await Task.sleep(for: .seconds(0.3))
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let ids = [window.windowNumber, ripple.windowNumber, keys.windowNumber].map(CGWindowID.init)
        guard let display = content.displays.first(where: { $0.displayID == ScreenCapturer.displayID(of: screen) }) else { return }
        let filter = SCContentFilter(display: display, including: content.windows.filter { ids.contains($0.windowID) })
        let config = SCStreamConfiguration()
        config.sourceRect = CGRect(x: rect.minX - screen.frame.minX, y: screen.frame.maxY - rect.maxY, width: rect.width, height: rect.height)
        config.width = Int(rect.width * 2)
        config.height = Int(rect.height * 2)
        config.showsCursor = false
        config.colorSpaceName = CGColorSpace.sRGB
        ripple.showRipple(at: CGPoint(x: 320, y: 340 - 176))
        try? await Task.sleep(for: .seconds(0.07))
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        let dir = URL(fileURLWithPath: "\(root)/\(lang)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: dir.appending(path: "overlay.png"))
        ripple.stop()
        keys.stop()
        window.orderOut(nil)
    }
}
