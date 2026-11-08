import AppKit

/// Non-activating floating HUD shown while the model runs; it never becomes key or main, so focus stays in the user's app.
@MainActor
enum ProgressHUD {
    private static let progressText = "FM Rephraser in progress..."
    private static let maxLabelWidth: CGFloat = 420

    private static var panel: NSPanel?
    private static var spinner: NSProgressIndicator?
    private static var label: NSTextField?
    private static var stack: NSStackView?
    private static var hideTask: Task<Void, Never>?

    static func show() {
        hideTask?.cancel()
        hideTask = nil
        present(text: progressText, spinning: true)
    }

    static func showError(_ message: String) {
        hideTask?.cancel()
        let text = message.count > 120 ? String(message.prefix(120)) + "..." : message
        present(text: text, spinning: false)
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled { hide() }
        }
    }

    static func hide() {
        hideTask?.cancel()
        hideTask = nil
        spinner?.stopAnimation(nil)
        panel?.orderOut(nil)
    }

    private static func present(text: String, spinning: Bool) {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        guard let label, let spinner, let stack else { return }

        label.stringValue = text
        let measured = label.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: maxLabelWidth, height: .greatestFiniteMagnitude))
        label.preferredMaxLayoutWidth = min(ceil(measured?.width ?? maxLabelWidth), maxLabelWidth)
        spinner.isHidden = !spinning
        if spinning { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }
        panel.setContentSize(stack.fittingSize)

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            let size = panel.frame.size
            panel.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2, y: visible.minY + visible.height * 0.15))
        }
        panel.orderFrontRegardless()
    }

    private static func makePanel() -> NSPanel {
        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isIndeterminate = true
        self.spinner = spinner

        let label = NSTextField(wrappingLabelWithString: progressText)
        label.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        label.maximumNumberOfLines = 2
        label.lineBreakMode = .byTruncatingTail
        label.cell?.truncatesLastVisibleLine = true
        self.label = label

        let stack = NSStackView(views: [spinner, label])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
        stack.autoresizingMask = [.width, .height]
        self.stack = stack

        let background = NSVisualEffectView()
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 10
        background.layer?.masksToBounds = true
        background.addSubview(stack)

        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 200, height: 40),
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
        stack.frame = background.bounds
        return panel
    }
}
