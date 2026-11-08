import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var accessibilityItems: [NSMenuItem] = []
    private var hotKey: HotKey?
    private var busy = false

    private let configURL = AppConfig.configURL
    private let instructionsURL = AppConfig.instructionsURL

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

    private func buildMenu(hotkeyLabel: String, backendLabel: String) {
        let menu = NSMenu()
        let info = Bundle.main.infoDictionary
        let buildID = info?["CFBundleVersion"] as? String ?? "unknown"
        let buildTime = info?["FMRBuildTime"] as? String ?? "unknown"
        menu.addItem(NSMenuItem(title: "FMRephraser \(buildID), built \(buildTime)", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Hotkey: \(hotkeyLabel)", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Backend: \(backendLabel)", action: nil, keyEquivalent: ""))
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
        let (spec, backendLabel) = AppConfig.load()

        hotKey = nil
        hotKey = HotKey(spec: spec) { [weak self] in self?.trigger() }
        buildMenu(hotkeyLabel: hotKey == nil ? "\(spec) (invalid or taken)" : spec, backendLabel: backendLabel)
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

enum AppConfig {
    static let directory: URL = {
        if let dir = ProcessInfo.processInfo.environment["FMR_CONFIG_DIR"], !dir.isEmpty {
            return URL(fileURLWithPath: (dir as NSString).expandingTildeInPath, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/fm-rephraser")
    }()
    static let configURL = directory.appendingPathComponent("config.json")
    static let instructionsURL = directory.appendingPathComponent("instructions.txt")

    /// Applies the instructions and backend to Rephraser; returns the hotkey spec and the backend menu label.
    static func load() -> (hotkey: String, backendLabel: String) {
        let config = (try? Data(contentsOf: configURL))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        let spec = config["hotkey"] as? String ?? "ctrl+t"
        let instructions = (try? String(contentsOf: instructionsURL, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        Rephraser.instructions = instructions.isEmpty ? Rephraser.defaultInstructions : instructions
        Secrets.clearCache()

        switch config["backend"] as? String ?? "local" {
        case "local":
            Rephraser.backend = .local
            return (spec, "on-device")
        case "remote":
            do {
                let remote = try RemoteLLMConfig(config["remote"] as? [String: Any] ?? [:])
                Rephraser.backend = .remote(remote)
                return (spec, "remote (\(remote.describe))")
            } catch {
                Rephraser.backend = .invalid(error)
                let message = if case RemoteLLMError.config(let detail) = error { detail } else { error.localizedDescription }
                return (spec, "remote (config error: \(message))")
            }
        case let name:
            let error = RephraseError.unknownBackend(name)
            Rephraser.backend = .invalid(error)
            return (spec, error.localizedDescription)
        }
    }
}

if CommandLine.arguments.dropFirst().first == "--rephrase" {
    guard CommandLine.arguments.count == 3 else {
        FileHandle.standardError.write(Data("usage: FMRephraser --rephrase <text>\n".utf8))
        exit(2)
    }
    let text = CommandLine.arguments[2]
    _ = AppConfig.load()
    Task {
        do {
            print(try await Rephraser.rephrase(text))
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("FMRephraser: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }
    dispatchMain()
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
