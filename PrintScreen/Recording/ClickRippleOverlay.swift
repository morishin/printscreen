import AppKit
import QuartzCore

/// 録画範囲の中でクリックした位置に波紋を出す。録画に映すウインドウで、マウス操作は素通しする。
final class ClickRippleOverlay {
    private let panel: NSPanel
    private let recordingRect: CGRect
    private var monitors: [Any] = []

    var windowNumber: Int { panel.windowNumber }

    init(recordingRect: CGRect) {
        self.recordingRect = recordingRect
        panel = NSPanel(contentRect: recordingRect, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        let view = NSView(frame: CGRect(origin: .zero, size: recordingRect.size))
        view.wantsLayer = true
        panel.contentView = view
    }

    func start() {
        panel.orderFrontRegardless()
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            self?.handleClick()
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            self?.handleClick()
            return event
        }) {
            monitors.append(local)
        }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        panel.orderOut(nil)
    }

    private func handleClick() {
        let location = NSEvent.mouseLocation
        guard recordingRect.contains(location) else { return }
        showRipple(at: CGPoint(x: location.x - recordingRect.minX, y: location.y - recordingRect.minY))
    }

    /// point はパネル内の座標（左下原点）。
    func showRipple(at point: CGPoint) {
        guard let host = panel.contentView?.layer else { return }
        let radius: CGFloat = 28
        let ripple = CAShapeLayer()
        ripple.frame = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
        ripple.path = CGPath(ellipseIn: CGRect(x: 0, y: 0, width: radius * 2, height: radius * 2), transform: nil)
        ripple.fillColor = NSColor.black.withAlphaComponent(0.22).cgColor
        ripple.strokeColor = NSColor.white.withAlphaComponent(0.95).cgColor
        ripple.lineWidth = 2
        ripple.shadowColor = NSColor.black.cgColor
        ripple.shadowOpacity = 0.6
        ripple.shadowRadius = 2
        ripple.shadowOffset = .zero
        ripple.opacity = 0
        host.addSublayer(ripple)

        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.25
        scale.toValue = 1
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        let group = CAAnimationGroup()
        group.animations = [scale, fade]
        group.duration = 0.5
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        ripple.add(group, forKey: "ripple")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            ripple.removeFromSuperlayer()
        }
    }
}
