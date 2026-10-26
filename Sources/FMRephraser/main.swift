import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var hotKey: HotKey?
    private var busy = false

    private let configURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/fm-rephraser/config.json")

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        setIcon("text.badge.checkmark")

        // Prompts for Accessibility permission on first launch (needed to send ⌘C / ⌘V).
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)

        reloadConfig()
    }

    private func setIcon(_ symbol: String) {
        statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "FM Rephraser")
    }

    private func buildMenu(hotkeyLabel: String) {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Hotkey: \(hotkeyLabel)", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Open Config", action: #selector(openConfig), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Reload Config", action: #selector(reloadConfig), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    @objc private func openConfig() {
        NSWorkspace.shared.open(configURL)
    }

    @objc private func reloadConfig() {
        if !FileManager.default.fileExists(atPath: configURL.path) {
            try? FileManager.default.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? #"{ "hotkey": "ctrl+t" }"#.write(to: configURL, atomically: true, encoding: .utf8)
        }
        let spec = (try? Data(contentsOf: configURL))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: String] }?["hotkey"] ?? "ctrl+t"

        hotKey = nil
        hotKey = HotKey(spec: spec) { [weak self] in self?.trigger() }
        buildMenu(hotkeyLabel: hotKey == nil ? "\(spec) (invalid or taken)" : spec)
    }

    private func trigger() {
        guard !busy else { return }
        busy = true
        setIcon("ellipsis.circle")
        Task { @MainActor in
            await Selection.run(Rephraser.rephrase)
            busy = false
            setIcon("text.badge.checkmark")
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
