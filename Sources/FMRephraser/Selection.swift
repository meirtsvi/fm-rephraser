import AppKit

/// Reads/replaces the selection in the frontmost app by simulating ⌘C / ⌘V (needs Accessibility permission).
enum Selection {
    private static let keyC: CGKeyCode = 0x08
    private static let keyV: CGKeyCode = 0x09

    static func run(_ transform: (String) async throws -> String) async {
        await waitForModifiersReleased()

        let pb = NSPasteboard.general
        let saved = snapshot(pb)
        defer { restore(pb, saved) }

        let before = pb.changeCount
        press(keyC)
        guard await waitForChange(pb, from: before), let text = pb.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            NSSound.beep()
            return
        }

        do {
            let result = try await transform(text)
            pb.clearContents()
            pb.setString(result, forType: .string)
            press(keyV)
            try? await Task.sleep(for: .milliseconds(300)) // let the target app read the pasteboard before restoring
        } catch {
            NSLog("FMRephraser: \(error)")
            NSSound.beep()
        }
    }

    private static func press(_ key: CGKeyCode) {
        let src = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: down)
            e?.flags = .maskCommand
            e?.post(tap: .cghidEventTap)
        }
    }

    /// The hotkey's modifiers (e.g. Ctrl) are usually still held; wait so they don't mix into ⌘C.
    private static func waitForModifiersReleased() async {
        let mask: CGEventFlags = [.maskControl, .maskCommand, .maskAlternate, .maskShift]
        for _ in 0..<50 {
            if CGEventSource.flagsState(.combinedSessionState).intersection(mask).isEmpty { return }
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    private static func waitForChange(_ pb: NSPasteboard, from count: Int) async -> Bool {
        for _ in 0..<50 {
            if pb.changeCount != count { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return false
    }

    private static func snapshot(_ pb: NSPasteboard) -> [NSPasteboardItem] {
        (pb.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        }
    }

    private static func restore(_ pb: NSPasteboard, _ items: [NSPasteboardItem]) {
        pb.clearContents()
        if !items.isEmpty { pb.writeObjects(items) }
    }
}
