# FMRephraser

A macOS menu bar app that fixes grammar and rephrases selected text in any app, using Apple's on-device Foundation Models. Select text (e.g. in Slack), press **Ctrl+T**, and the selection is replaced with the corrected version. Nothing leaves your Mac.

Links and @mentions are kept exactly as written. If the model changes or drops one, the text is left untouched and you hear a beep.

## Requirements

- macOS 26 or later with Apple Intelligence enabled
- Apple Silicon Mac
- For building from source: Xcode 26+ (or its Command Line Tools)

## Install

### From source

```sh
git clone https://github.com/meirtsvi/fm-rephraser.git
cd fm-rephraser
./install.sh
```

This builds the app, copies it to `/Applications`, adds it to Login Items and starts it.

### Prebuilt

Download `FMRephraser.zip` from the [latest release](https://github.com/meirtsvi/fm-rephraser/releases/latest), unzip it and move `FMRephraser.app` to `/Applications`. The app is not notarized, so remove the quarantine flag before opening it:

```sh
xattr -dr com.apple.quarantine /Applications/FMRephraser.app
open /Applications/FMRephraser.app
```

To start it at login: System Settings → General → Login Items → **+** → FMRephraser.

### Accessibility permission

On first launch, allow FMRephraser in System Settings → Privacy & Security → Accessibility. It needs this to send ⌘C / ⌘V to the frontmost app. After reinstalling or rebuilding, you may need to remove and re-add it there.

If the menu shows "Accessibility permission is missing or stale", the hotkey cannot copy or paste: choose **Open Accessibility Settings** and enable FMRephraser (or remove and re-add it after a rebuild).

## Usage

1. Select text in any app.
2. Press the hotkey (default **Ctrl+T**). The menu bar icon shows `…` while working, and a small "FM Rephraser in progress..." overlay appears near the bottom of the screen (it does not take focus).
3. The selection is replaced. Your clipboard is restored afterwards.

With no selection, the whole content of the focused text field is rephrased.

## Configuration

Edit `~/.config/fm-rephraser/config.json` (menu bar icon → Open Config), then choose **Reload Config**:

```json
{ "hotkey": "ctrl+option+r" }
```

Modifiers: `ctrl`, `cmd`, `option`, `shift`. Keys: letters, digits, `space`.

Note: the default Ctrl+T replaces the macOS "transpose characters" shortcut in text fields.

### Custom prompt

To replace the prompt sent to the model, put your own in `~/.config/fm-rephraser/instructions.txt`. It is plain text, so paste a multi-line prompt as-is, with no escaping. Menu bar icon → **Open Instructions** opens the file, creating it pre-filled with the default prompt if it does not exist yet. Choose **Reload Config** to apply changes without restarting.

The file replaces the whole default prompt, so include everything you still want (for example keeping links and @mentions intact). Delete or empty the file to return to the default, which lives in `defaultInstructions` in `Sources/FMRephraser/Rephraser.swift`. Links and @mentions are still checked after every response regardless of the prompt.

The on-device model has a limited context window (about 4096 tokens, covering the prompt, the selected text and the reply), so a very long prompt leaves less room for the text.

## Limitations

- Works on plain text. Rich formatting (bold, hyperlinks with custom display text) is lost in the replaced text.
- Clipboard managers will see the intermediate copy/paste.
