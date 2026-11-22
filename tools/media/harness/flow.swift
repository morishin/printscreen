import AppKit
import AVFoundation
import ScreenCaptureKit

// サイト用デモ動画の撮影コード。tools/media/media.sh で一時的にアプリへ組み込む。
enum TempShots {
    static var root: String { UserDefaults.standard.string(forKey: "TempOut") ?? NSTemporaryDirectory() }
    static let stageSize = CGSize(width: 1440, height: 900)
    static let selection = CGRect(x: 170, y: 92, width: 1100, height: 718)

    struct Copy {
        let appTitle, heading, sub, name, nameValue, email, emailValue, password, button, foot, note: String
    }

    static func copy(_ lang: String) -> Copy {
        if lang == "ja" {
            return Copy(appTitle: "サンプルアプリ", heading: "アカウントを作成", sub: "メールアドレスで登録できます",
                        name: "名前", nameValue: "山田 葵", email: "メールアドレス", emailValue: "aoi@example.com",
                        password: "パスワード", button: "アカウントを作成", foot: "すでにアカウントをお持ちの方はログイン", note: "ここを押す！")
        }
        return Copy(appTitle: "Sample App", heading: "Create your account", sub: "Sign up with your email address",
                    name: "Name", nameValue: "Avery Clark", email: "Email", emailValue: "avery@example.com",
                    password: "Password", button: "Create account", foot: "Already have an account? Sign in", note: "Click here!")
    }

    static func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat(hex >> 16 & 255) / 255, green: CGFloat(hex >> 8 & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: alpha)
    }

    static func stage(_ c: Copy) -> CGImage {
        let (w, h) = (stageSize.width, stageSize.height)
        let ctx = CGContext(data: nil, width: Int(w * 2), height: Int(h * 2), bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.scaleBy(x: 2, y: 2)
        ctx.translateBy(x: 0, y: h)
        ctx.scaleBy(x: 1, y: -1)
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        NSGradient(colors: [color(0x6E8F7B), color(0xC9B98F), color(0xE7D9B8)])!.draw(in: CGRect(x: 0, y: 0, width: w, height: h), angle: 62)
        func fill(_ r: CGRect, _ c: NSColor, radius: CGFloat = 0) {
            c.setFill()
            NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius).fill()
        }
        func text(_ s: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat, _ hex: UInt32, _ weight: NSFont.Weight = .regular, center: CGFloat? = nil) {
            let a = NSAttributedString(string: s, attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color(hex)])
            a.draw(at: CGPoint(x: center.map { $0 - a.size().width / 2 } ?? x, y: y))
        }
        let win = CGRect(x: 190, y: 110, width: 1060, height: 680)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = color(0x000000, 0.35)
        shadow.shadowBlurRadius = 30
        shadow.shadowOffset = CGSize(width: 0, height: 14)
        shadow.set()
        fill(win, color(0xFFFFFF), radius: 14)
        NSGraphicsContext.restoreGraphicsState()
        NSBezierPath(roundedRect: win, xRadius: 14, yRadius: 14).addClip()
        fill(CGRect(x: win.minX, y: win.minY, width: win.width, height: 44), color(0xF0F0F2))
        for (i, hex) in [UInt32(0xFF5F57), 0xFEBC2E, 0x28C840].enumerated() {
            fill(CGRect(x: win.minX + 16 + CGFloat(i) * 20, y: win.minY + 16, width: 12, height: 12), color(hex), radius: 6)
        }
        let cx = win.midX
        text(c.appTitle, 0, win.minY + 13, 13, 0x5F6368, .semibold, center: cx)
        text(c.heading, 0, 196, 32, 0x1F2430, .bold, center: cx)
        text(c.sub, 0, 248, 16, 0x6B7280, center: cx)
        let fx: CGFloat = 470, fw: CGFloat = 500
        for (label, value, y) in [(c.name, c.nameValue, CGFloat(306)), (c.email, c.emailValue, 394), (c.password, "••••••••••", 482)] {
            text(label, fx, y, 14, 0x3F4653, .semibold)
            let field = CGRect(x: fx, y: y + 26, width: fw, height: 44)
            fill(field, color(0xF6F7F9), radius: 8)
            color(0xD8DBE2).setStroke()
            NSBezierPath(roundedRect: field.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8).stroke()
            text(value, fx + 14, y + 37, 16, 0x1F2430)
        }
        fill(CGRect(x: fx, y: 590, width: fw, height: 52), color(0x2F6FED), radius: 9)
        text(c.button, 0, 605, 17, 0xFFFFFF, .semibold, center: cx)
        text(c.foot, 0, 668, 14, 0x6B7280, center: cx)
        NSGraphicsContext.current = nil
        return ctx.makeImage()!
    }

    static func wait(_ s: Double) async { try? await Task.sleep(for: .seconds(s)) }

    static func run(lang: String) {
        Task {
            do { try await record(lang) } catch {
                try? "\(error)".write(toFile: "\(root)/error-video-\(lang).txt", atomically: true, encoding: .utf8)
            }
            exit(0)
        }
    }

    static func record(_ lang: String) async throws {
        guard let screen = NSScreen.main else { return }
        let c = copy(lang)
        let v = screen.visibleFrame
        let rect = CGRect(x: v.maxX - stageSize.width, y: v.minY, width: stageSize.width, height: stageSize.height)
        func S(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x, y: rect.maxY - y) }
        let image = stage(c)

        let stageWindow = NSWindow(contentRect: rect, styleMask: .borderless, backing: .buffered, defer: false)
        stageWindow.isReleasedWhenClosed = false
        stageWindow.level = .floating
        let imageView = NSImageView(image: NSImage(cgImage: image, size: stageSize))
        imageView.imageScaling = .scaleAxesIndependently
        stageWindow.contentView = imageView
        stageWindow.orderFrontRegardless()

        // トーストと重ならないよう、キー表示はその上に出す
        let keys = KeystrokeOverlay(recordingRect: CGRect(x: rect.minX, y: rect.minY + 76, width: rect.width, height: rect.height - 76))
        keys.start()

        let cursorPanel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 40, height: 40), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        cursorPanel.isOpaque = false
        cursorPanel.backgroundColor = .clear
        cursorPanel.hasShadow = false
        cursorPanel.ignoresMouseEvents = true
        cursorPanel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        let cursorView = NSImageView(frame: CGRect(x: 0, y: 0, width: 40, height: 40))
        cursorView.imageAlignment = .alignTopLeft
        cursorView.imageScaling = .scaleNone
        cursorPanel.contentView = cursorView
        var currentCursor = NSCursor.arrow
        var position = S(1120, 250)
        func place(_ p: CGPoint) {
            position = p
            cursorPanel.setFrameOrigin(CGPoint(x: p.x - currentCursor.hotSpot.x, y: p.y + currentCursor.hotSpot.y - 40))
        }
        func setCursor(_ cursor: NSCursor) {
            currentCursor = cursor
            cursorView.image = cursor.image
            place(position)
        }
        setCursor(.arrow)
        cursorPanel.orderFrontRegardless()
        func move(_ to: CGPoint, _ duration: Double = 0.6, each: ((CGPoint) -> Void)? = nil) async {
            let from = position, steps = max(1, Int(duration * 60))
            for i in 1...steps {
                let t = Double(i) / Double(steps), e = CGFloat(t * t * (3 - 2 * t))
                let p = CGPoint(x: from.x + (to.x - from.x) * e, y: from.y + (to.y - from.y) * e)
                place(p)
                each?(p)
                await wait(1.0 / 60)
            }
        }
        await wait(0.5)

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == ScreenCapturer.displayID(of: screen) }),
              let app = content.applications.first(where: { $0.processID == ProcessInfo.processInfo.processIdentifier }) else { return }
        let config = SCStreamConfiguration()
        config.sourceRect = CGRect(x: rect.minX - screen.frame.minX, y: screen.frame.maxY - rect.maxY, width: rect.width, height: rect.height)
        config.width = 1920
        config.height = 1200
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.showsCursor = false
        config.colorSpaceName = CGColorSpace.sRGB
        let filter = SCContentFilter(display: display, including: [app], exceptingWindows: [])
        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        let url = URL(fileURLWithPath: "\(root)/\(lang)/flow-raw.mp4")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: url)
        let outputConfig = SCRecordingOutputConfiguration()
        outputConfig.outputURL = url
        outputConfig.outputFileType = .mp4
        outputConfig.videoCodecType = .h264
        let delegate = Delegate()
        try stream.addRecordingOutput(SCRecordingOutput(configuration: outputConfig, delegate: delegate))
        try await stream.startCapture()
        await wait(0.8)

        // ⌘⇧4 → 範囲をドラッグ
        keys.model.push(text: "⌘⇧4", isCombo: true)
        let overlay = SelectionWindow(screen: screen)
        overlay.ignoresMouseEvents = true
        overlay.orderFrontRegardless()
        setCursor(.crosshair)
        func viewPoint(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x - screen.frame.minX, y: p.y - screen.frame.minY) }
        await move(S(selection.minX, selection.minY), 0.7) { p in
            overlay.selectionView.mouse = viewPoint(p)
            overlay.selectionView.needsDisplay = true
        }
        await wait(0.2)
        overlay.selectionView.start = viewPoint(position)
        await move(S(selection.maxX, selection.maxY), 1.1) { p in
            overlay.selectionView.current = viewPoint(p)
            overlay.selectionView.needsDisplay = true
        }
        await wait(0.3)
        overlay.orderOut(nil)
        await wait(0.1)
        let crop = image.cropping(to: CGRect(x: selection.minX * 2, y: selection.minY * 2, width: selection.width * 2, height: selection.height * 2))!

        // 編集画面
        stageWindow.level = .normal
        EditorWindowController.open(image: crop, pixelScale: 2)
        guard let controller = EditorWindowController.openControllers.first, let editor = controller.window else { return }
        editor.level = .floating
        editor.setFrameOrigin(CGPoint(x: rect.midX - editor.frame.width / 2, y: rect.midY - editor.frame.height / 2))
        setCursor(.arrow)
        // 録画中はシステムの録画インジケータが信号機ボタンに重なるので、動画では通常の見た目を重ねる
        let lightsFrame = CGRect(x: editor.frame.minX + 12, y: editor.frame.maxY - 42, width: 76, height: 34)
        let lights = NSPanel(contentRect: lightsFrame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        lights.isOpaque = false
        lights.backgroundColor = .clear
        lights.hasShadow = false
        lights.ignoresMouseEvents = true
        lights.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        let lightsView = NSView(frame: CGRect(origin: .zero, size: lightsFrame.size))
        lightsView.wantsLayer = true
        lightsView.layer?.backgroundColor = color(0x20242B).cgColor
        lightsView.layer?.cornerRadius = 8
        for (i, hex) in [UInt32(0xFF5F57), 0xFEBC2E, 0x28C840].enumerated() {
            let dot = NSView(frame: CGRect(x: 7 + CGFloat(i) * 23, y: 10, width: 14, height: 14))
            dot.wantsLayer = true
            dot.layer?.backgroundColor = color(hex).cgColor
            dot.layer?.cornerRadius = 7
            lightsView.addSubview(dot)
        }
        lights.contentView = lightsView
        lights.orderFrontRegardless()
        await wait(0.7)
        let contentFrame = editor.convertToScreen(editor.contentView!.frame)
        let imageLeft = contentFrame.midX - selection.width / 2, imageTop = contentFrame.midY + selection.height / 2
        func E(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: imageLeft + x - selection.minX, y: imageTop - (y - selection.minY)) }
        func I(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: (x - selection.minX) * 2, y: (y - selection.minY) * 2) }
        func IR(_ a: CGPoint, _ b: CGPoint) -> CGRect { CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y)) }
        let m = controller.model
        let red = PaletteColor.all[0].color

        // 枠
        m.tool = .rect
        await move(E(458, 580), 0.55)
        var a = Annotation(shape: .rect(IR(I(458, 580), I(459, 581))), color: red, lineWidth: 8)
        m.add(a)
        await move(E(982, 652), 0.6) { p in
            let x = p.x - imageLeft + selection.minX, y = imageTop - p.y + selection.minY
            m.update(a.id) { $0.shape = .rect(IR(I(458, 580), I(x, y))) }
        }
        await wait(0.2)

        // 矢印
        m.tool = .arrow
        await move(E(1140, 470), 0.5)
        a = Annotation(shape: .arrow(I(1140, 470), I(1139, 471)), color: red, lineWidth: 8)
        m.add(a)
        await move(E(996, 596), 0.5) { p in
            let x = p.x - imageLeft + selection.minX, y = imageTop - p.y + selection.minY
            m.update(a.id) { $0.shape = .arrow(I(1140, 470), I(x, y)) }
        }
        await wait(0.2)

        // 文字
        m.tool = .text
        await move(E(1010, 405), 0.45)
        a = Annotation(shape: .text(origin: I(1010, 405), string: "", fontSize: 56), color: red, lineWidth: 8)
        m.add(a)
        var typed = ""
        for ch in c.note {
            typed.append(ch)
            m.update(a.id) { $0.shape = .text(origin: I(1010, 405), string: typed, fontSize: 56) }
            await wait(0.075)
        }
        await wait(0.25)

        // モザイク
        m.tool = .mosaic
        await move(E(478, 424), 0.55)
        a = Annotation(shape: .mosaic(IR(I(478, 424), I(479, 425))), color: red, lineWidth: 8)
        m.add(a)
        await move(E(760, 460), 0.55) { p in
            let x = p.x - imageLeft + selection.minX, y = imageTop - p.y + selection.minY
            m.update(a.id) { $0.shape = .mosaic(IR(I(478, 424), I(x, y))) }
        }
        m.tool = .select
        await wait(0.5)
        let finalAnnotations = m.annotations

        // 保存（実ファイルは作らない）
        keys.model.push(text: "⌘S", isCombo: true)
        await wait(0.3)
        m.isSaved = true
        lights.orderOut(nil)
        editor.close()
        let name = OutputFiles.baseName(prefix: String(localized: "Screenshot"), date: .now) + ".webp"
        Toast.show(String(localized: "Saved"), detail: name, fileURL: URL(fileURLWithPath: "/tmp/\(name)"))
        await move(S(1120, 250), 0.9)
        await wait(1.3)
        Toast.hide()
        await wait(0.4)

        try await stream.stopCapture()
        await wait(1.2)
        _ = delegate
        keys.stop()
        cursorPanel.orderOut(nil)

        // 静止画は録画を止めてから撮り直す（録画インジケータを写さない）
        EditorWindowController.open(image: crop, pixelScale: 2)
        await wait(0.8)
        if let still = EditorWindowController.openControllers.first, let stillWindow = still.window {
            stillWindow.level = .floating
            still.model.annotations = finalAnnotations
            still.model.tool = .select
            await wait(0.8)
            let shot = try await ScreenCapturer.capture(window: WindowSelection(windowID: CGWindowID(stillWindow.windowNumber), rect: stillWindow.frame))
            try NSBitmapImageRep(cgImage: shot).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(root)/\(lang)/flow-editor.png"))
            still.model.isSaved = true
            stillWindow.close()
        }
        stageWindow.orderOut(nil)
    }

    final class Delegate: NSObject, SCRecordingOutputDelegate {}
}
