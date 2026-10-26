import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var accessibilityItems: [NSMenuItem] = []
    private var hotKey: HotKey?
    private var busy = false

    private let configURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/fm-rephraser/config.json")
    private let instructionsURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/fm-rephraser/instructions.txt")

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
        accessibilityItems = [
            NSMenuItem(title: "Accessibility permission is missing or stale", action: nil, keyEquivalent: ""),
            NSMenuItem(title: "Open Accessibility Settings", action: #selector(openAccessibilitySettings), keyEquivalent: ""),
        ]
        accessibilityItems.forEach(menu.addItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Open Config", action: #selector(openConfig), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Open Instructions", action: #selector(openInstructions), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Reload Config", action: #selector(reloadConfig), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        menu.delegate = self
        statusItem.menu = menu
        menuWillOpen(menu)
    }

    func menuWillOpen(_ menu: NSMenu) {
        let trusted = AXIsProcessTrusted()
        accessibilityItems.forEach { $0.isHidden = trusted }
    }

    @objc private func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc private func openConfig() {
        NSWorkspace.shared.open(configURL)
    }

    @objc private func openInstructions() {
        if !FileManager.default.fileExists(atPath: instructionsURL.path) {
            try? FileManager.default.createDirectory(at: instructionsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? Rephraser.defaultInstructions.write(to: instructionsURL, atomically: true, encoding: .utf8)
        }
        NSWorkspace.shared.open(instructionsURL)
    }

    @objc private func reloadConfig() {
        if !FileManager.default.fileExists(atPath: configURL.path) {
            try? FileManager.default.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? #"{ "hotkey": "ctrl+t" }"#.write(to: configURL, atomically: true, encoding: .utf8)
        }
        let config = (try? Data(contentsOf: configURL))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        let spec = config["hotkey"] as? String ?? "ctrl+t"
        let instructions = (try? String(contentsOf: instructionsURL, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        Rephraser.instructions = instructions.isEmpty ? Rephraser.defaultInstructions : instructions

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
