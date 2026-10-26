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

## Usage

1. Select text in any app.
2. Press the hotkey (default **Ctrl+T**). The menu bar icon shows `…` while working.
3. The selection is replaced. Your clipboard is restored afterwards.

## Configuration

Edit `~/.config/fm-rephraser/config.json` (menu bar icon → Open Config), then choose **Reload Config**:

```json
{ "hotkey": "ctrl+option+r" }
```

Modifiers: `ctrl`, `cmd`, `option`, `shift`. Keys: letters, digits, `space`.

Note: the default Ctrl+T replaces the macOS "transpose characters" shortcut in text fields.

## Limitations

- Works on plain text. Rich formatting (bold, hyperlinks with custom display text) is lost in the replaced text.
- Clipboard managers will see the intermediate copy/paste.
