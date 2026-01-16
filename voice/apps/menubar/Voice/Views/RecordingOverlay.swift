import Cocoa

class RecordingOverlay {
    private var overlayWindows: [NSWindow] = []

    func show() {
        DispatchQueue.main.async { [weak self] in
            self?.doShow()
        }
    }

    func hide() {
        DispatchQueue.main.async { [weak self] in
            self?.doHide()
        }
    }

    private func doShow() {
        guard overlayWindows.isEmpty else { return }

        for screen in NSScreen.screens {
            let window = createOverlayWindow(for: screen)
            window.orderFrontRegardless()
            overlayWindows.append(window)
        }
    }

    private func doHide() {
        for window in overlayWindows {
            window.orderOut(nil)
        }
        overlayWindows.removeAll()
    }

    private func createOverlayWindow(for screen: NSScreen) -> NSWindow {
        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        window.level = .screenSaver
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let overlayView = RecordingOverlayView(frame: screen.frame)
        window.contentView = overlayView

        return window
    }
}

class RecordingOverlayView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let borderWidth: CGFloat = 6
        let glowColor = NSColor.systemRed.withAlphaComponent(0.7)

        let path = NSBezierPath()
        path.appendRect(NSRect(x: 0, y: bounds.height - borderWidth, width: bounds.width, height: borderWidth))
        path.appendRect(NSRect(x: 0, y: 0, width: bounds.width, height: borderWidth))
        path.appendRect(NSRect(x: 0, y: 0, width: borderWidth, height: bounds.height))
        path.appendRect(NSRect(x: bounds.width - borderWidth, y: 0, width: borderWidth, height: bounds.height))

        glowColor.setFill()
        path.fill()
    }
}
