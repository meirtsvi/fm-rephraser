import AppKit

/// Non-activating floating HUD shown while the model runs; it never becomes key or main, so focus stays in the user's app.
@MainActor
enum ProgressHUD {
    private static var panel: NSPanel?
    private static var spinner: NSProgressIndicator?

    static func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            let size = panel.frame.size
            panel.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2, y: visible.minY + visible.height * 0.15))
        }
        spinner?.startAnimation(nil)
        panel.orderFrontRegardless()
    }

    static func hide() {
        spinner?.stopAnimation(nil)
        panel?.orderOut(nil)
    }

    private static func makePanel() -> NSPanel {
        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isIndeterminate = true
        self.spinner = spinner

        let label = NSTextField(labelWithString: "FM Rephraser in progress...")
        label.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .medium)

        let stack = NSStackView(views: [spinner, label])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
        let size = stack.fittingSize

        let background = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 10
        background.layer?.masksToBounds = true
        stack.frame = background.bounds
        background.addSubview(stack)

        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.contentView = background
        return panel
    }
}
