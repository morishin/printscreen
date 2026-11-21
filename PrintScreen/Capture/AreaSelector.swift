import AppKit

/// 選択された範囲。rect は AppKit のグローバル座標（左下原点、ポイント）。
struct AreaSelection {
    let screen: NSScreen
    let rect: CGRect

    /// ScreenCaptureKit の sourceRect 用（ディスプレイ左上原点、ポイント）。
    var displayLocalRect: CGRect {
        CGRect(x: rect.minX - screen.frame.minX,
               y: screen.frame.maxY - rect.maxY,
               width: rect.width, height: rect.height)
    }
}

/// 選択されたウインドウ。rect は AppKit のグローバル座標（左下原点、ポイント）。
struct WindowSelection {
    let windowID: CGWindowID
    let rect: CGRect

    /// ウインドウが最も大きく重なっている画面の倍率。
    var pixelScale: CGFloat {
        let area: (NSScreen) -> CGFloat = { screen in
            let overlap = screen.frame.intersection(self.rect)
            return overlap.isNull ? 0 : overlap.width * overlap.height
        }
        return NSScreen.screens.max { area($0) < area($1) }?.backingScaleFactor ?? 2
    }

    /// 通常のウインドウを手前から順に返す。
    static func onScreenWindows() -> [WindowSelection] {
        guard let infos = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                     kCGNullWindowID) as? [[String: Any]],
              let primaryHeight = NSScreen.screens.first?.frame.height else { return [] }
        return infos.compactMap { info in
            guard info[kCGWindowLayer as String] as? Int == 0,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let id = info[kCGWindowNumber as String] as? CGWindowID,
                  let boundsInfo = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsInfo),
                  bounds.width >= 40, bounds.height >= 40 else { return nil }
            // CoreGraphics は左上原点なので AppKit の左下原点に変換する
            let rect = CGRect(x: bounds.minX, y: primaryHeight - bounds.maxY,
                              width: bounds.width, height: bounds.height)
            return WindowSelection(windowID: id, rect: rect)
        }
    }
}

enum CaptureTarget {
    case area(AreaSelection)
    case window(WindowSelection)
}

/// 全画面に半透明のオーバーレイを出し、ドラッグで範囲を選ばせる。Esc でキャンセル。
/// 静止画ではスペースキーでウインドウ選択に切り替えられる。
@MainActor
final class AreaSelector {
    private var windows: [SelectionWindow] = []
    private var continuation: CheckedContinuation<CaptureTarget?, Never>?
    private var isWindowMode = false
    private var windowCandidates: [WindowSelection] = []
    private var hoveredWindow: WindowSelection?

    /// 録画用。範囲選択のみ。
    static func select() async -> AreaSelection? {
        guard case .area(let selection)? = await run(allowsWindowMode: false) else { return nil }
        return selection
    }

    /// 静止画用。範囲またはウインドウを選ぶ。
    static func selectCaptureTarget() async -> CaptureTarget? {
        await run(allowsWindowMode: true)
    }

    private static func run(allowsWindowMode: Bool) async -> CaptureTarget? {
        let selector = AreaSelector()
        return await withCheckedContinuation { cont in
            selector.continuation = cont
            selector.show(allowsWindowMode: allowsWindowMode)
        }
    }

    private func toggleWindowMode() {
        isWindowMode.toggle()
        windowCandidates = isWindowMode ? WindowSelection.onScreenWindows() : []
        for w in windows { w.selectionView.isWindowMode = isWindowMode }
        updateHoveredWindow()
    }

    private func updateHoveredWindow() {
        let mouse = NSEvent.mouseLocation
        hoveredWindow = windowCandidates.first { $0.rect.contains(mouse) }
        for w in windows {
            w.selectionView.highlightRect = hoveredWindow.map { w.convertFromScreen($0.rect) }
        }
    }

    private func pickHoveredWindow() {
        updateHoveredWindow()
        guard let hoveredWindow else { return }
        finish(.window(hoveredWindow))
    }

    private func show(allowsWindowMode: Bool) {
        for screen in NSScreen.screens {
            let window = SelectionWindow(screen: screen)
            window.selectionView.onFinish = { [weak self] rect in
                self?.finish(rect.map { .area(AreaSelection(screen: screen, rect: $0)) })
            }
            if allowsWindowMode {
                window.selectionView.onToggleWindowMode = { [weak self] in self?.toggleWindowMode() }
            }
            window.selectionView.onWindowHover = { [weak self] in self?.updateHoveredWindow() }
            window.selectionView.onPickWindow = { [weak self] in self?.pickHoveredWindow() }
            window.orderFrontRegardless()
            windows.append(window)
        }
        NSApp.activate(ignoringOtherApps: true)
        // マウスがある画面のウインドウをキーにする
        let mouse = NSEvent.mouseLocation
        (windows.first { $0.frame.contains(mouse) } ?? windows.first)?.makeKey()
        NSCursor.crosshair.push()
    }

    private func finish(_ selection: CaptureTarget?) {
        guard let continuation else { return }
        self.continuation = nil
        NSCursor.pop()
        for w in windows { w.orderOut(nil) }
        windows.removeAll()
        // オーバーレイが画面から消えるのを待ってから撮る
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            continuation.resume(returning: selection)
        }
    }
}

private final class SelectionWindow: NSPanel {
    let selectionView: SelectionView

    init(screen: NSScreen) {
        selectionView = SelectionView(frame: CGRect(origin: .zero, size: screen.frame.size))
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        setFrame(screen.frame, display: false)
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        contentView = selectionView
    }

    override var canBecomeKey: Bool { true }
}

private final class SelectionView: NSView {
    var onFinish: ((CGRect?) -> Void)?
    var onToggleWindowMode: (() -> Void)?
    var onWindowHover: (() -> Void)?
    var onPickWindow: (() -> Void)?
    var isWindowMode = false {
        didSet {
            start = nil
            current = nil
            currentCursor.set()
            needsDisplay = true
        }
    }
    /// ウインドウ選択中にハイライトする範囲（ビュー座標）。
    var highlightRect: CGRect? {
        didSet { if highlightRect != oldValue { needsDisplay = true } }
    }
    private var currentCursor: NSCursor { isWindowMode ? .pointingHand : .crosshair }
    private var start: CGPoint?
    private var current: CGPoint?
    private var mouse: CGPoint?

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect, .cursorUpdate],
                                       owner: self))
    }

    override func cursorUpdate(with event: NSEvent) { currentCursor.set() }

    private var selectionRect: CGRect? {
        guard let start, let current else { return nil }
        return CGRect(x: min(start.x, current.x), y: min(start.y, current.y),
                      width: abs(start.x - current.x), height: abs(start.y - current.y)).integral
    }

    override func mouseMoved(with event: NSEvent) {
        if isWindowMode {
            currentCursor.set()
            onWindowHover?()
            return
        }
        mouse = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        guard !isWindowMode else { return }
        start = convert(event.locationInWindow, from: nil)
        current = start
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard !isWindowMode else { onWindowHover?(); return }
        current = convert(event.locationInWindow, from: nil)
        mouse = current
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if isWindowMode {
            onPickWindow?()
            return
        }
        current = convert(event.locationInWindow, from: nil)
        guard let rect = selectionRect, let window else { onFinish?(nil); return }
        if rect.width < 4 || rect.height < 4 {
            // クリックだけなら選び直し
            start = nil; current = nil
            needsDisplay = true
            return
        }
        onFinish?(window.convertToScreen(rect))
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Esc
            onFinish?(nil)
        } else if event.keyCode == 49, !event.isARepeat, start == nil { // Space（ドラッグ中は無視）
            onToggleWindowMode?()
        }
    }

    override func rightMouseDown(with event: NSEvent) { onFinish?(nil) }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.25).setFill()
        bounds.fill()
        if isWindowMode {
            if let highlightRect {
                NSColor.clear.setFill()
                highlightRect.fill(using: .copy)
                NSColor.systemBlue.withAlphaComponent(0.3).setFill()
                highlightRect.fill(using: .sourceOver)
            }
            return
        }
        if let rect = selectionRect {
            NSColor.clear.setFill()
            rect.fill(using: .copy)
            NSColor.white.setStroke()
            let path = NSBezierPath(rect: rect.insetBy(dx: -0.5, dy: -0.5))
            path.lineWidth = 1
            path.stroke()
            drawLabel("\(Int(rect.width)) × \(Int(rect.height))",
                      at: CGPoint(x: rect.maxX + 8, y: rect.minY - 24))
        } else if let mouse {
            drawLabel("\(Int(mouse.x)), \(Int(bounds.height - mouse.y))",
                      at: CGPoint(x: mouse.x + 14, y: mouse.y - 28))
        }
    }

    private func drawLabel(_ text: String, at point: CGPoint) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        let size = str.size()
        var origin = point
        origin.x = min(max(4, origin.x), bounds.width - size.width - 12)
        origin.y = min(max(4, origin.y), bounds.height - size.height - 8)
        let bg = CGRect(x: origin.x - 4, y: origin.y - 2, width: size.width + 8, height: size.height + 4)
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: bg, xRadius: 4, yRadius: 4).fill()
        str.draw(at: origin)
    }
}
