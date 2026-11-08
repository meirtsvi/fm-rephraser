# FMRephraser

A macOS menu bar app that fixes grammar and rephrases selected text in any app, using Apple's on-device Foundation Models. Select text (e.g. in Slack), press **Ctrl+T**, and the selection is replaced with the corrected version. With the default on-device backend nothing leaves your Mac; an optional remote LLM backend is also available (see [Remote LLM](#remote-llm)).

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

### Stable code signing

Each ad-hoc signed rebuild gets a new code signature, which invalidates the Accessibility grant, so you have to remove and re-add the app after every build. To avoid this, `build.sh` signs with a stable identity named "FMRephraser Local" when one exists in your keychain, and falls back to ad-hoc signing otherwise.

To create it: Keychain Access > Certificate Assistant > Create a Certificate, name it `FMRephraser Local`, Identity Type **Self Signed Root**, Certificate Type **Code Signing**. To use a different identity, set `FMR_SIGN_IDENTITY` (for example `FMR_SIGN_IDENTITY="Apple Development: Your Name" ./install.sh`). After switching to a stable identity, re-grant Accessibility once; later rebuilds keep the grant.

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

With the on-device backend, the model has a limited context window (about 4096 tokens, covering the prompt, the selected text and the reply), so a very long prompt leaves less room for the text. The remote backend has no such practical limit.

### Remote LLM

By default the text is rephrased on device. To send it to a remote LLM instead, set `"backend": "remote"` and add a `remote` section, then choose **Reload Config**. The menu shows the active backend, for example `Backend: remote (openai, claude-sonnet-4.6)`, or `Backend: remote (config error: ...)` when the section is invalid (the hotkey then shows the error and beeps).

```json
{
  "hotkey": "cmd+opt+p",
  "backend": "remote",
  "remote": {
    "api": "openai",
    "url": "https://llm-gateway.jfrogdev.org/v1/chat/completions",
    "model": "claude-sonnet-4.6",
    "temperature": 0.3,
    "maxTokens": 2048,
    "timeoutSeconds": 30,
    "secret": { "source": "keychain", "service": "fm-rephraser", "account": "llm" }
  }
}
```

| Key | Default | Meaning |
| --- | --- | --- |
| `backend` | `local` | `local` (on-device Foundation Models) or `remote` |
| `remote.api` | `openai` | `openai` (any OpenAI-compatible chat completions endpoint), `azure` or `anthropic` |
| `remote.url` | per api | `openai`: `https://api.openai.com/v1/chat/completions`; `anthropic`: `https://api.anthropic.com/v1/messages`; `azure`: required, the resource endpoint such as `https://my-resource.openai.azure.com` |
| `remote.model` | required | Model name; for `azure`, the deployment name |
| `remote.apiVersion` | empty | Required for `azure`, for example `2025-01-01-preview` |
| `remote.temperature` | `0.3` | Sampling temperature |
| `remote.maxTokens` | `2048` | Reply limit; sent as `max_completion_tokens` for `gpt-5` and later, otherwise `max_tokens` |
| `remote.timeoutSeconds` | `30` | Request timeout |
| `remote.secret.source` | `keychain` | Where the API key comes from: `keychain`, `env` or `file` |
| `remote.secret.service` | `fm-rephraser` | Keychain service |
| `remote.secret.account` | `llm` | Keychain account |
| `remote.secret.env` | `FM_REPHRASES_LLM_SECRET` | Environment variable name |
| `remote.secret.file` | `~/.config/fm-rephraser/.env-secret` | File holding only the key |

The key is read on every request, so changing it needs no reload. It is never logged or shown. Links and @mentions are checked the same way as with the on-device model. Errors (HTTP status with the provider's message, timeout, network failure) appear in the overlay for a few seconds.

#### Examples

JFrog LLM gateway (OpenAI-compatible):

```json
"remote": { "api": "openai", "url": "https://llm-gateway.jfrogdev.org/v1/chat/completions", "model": "claude-sonnet-4.6" }
```

OpenAI:

```json
"remote": { "api": "openai", "model": "gpt-4.1" }
```

Azure OpenAI (`model` is the deployment name; the request goes to `{url}/openai/deployments/{model}/chat/completions?api-version={apiVersion}`):

```json
"remote": { "api": "azure", "url": "https://my-resource.openai.azure.com", "model": "gpt-4o", "apiVersion": "2025-01-01-preview" }
```

Anthropic:

```json
"remote": { "api": "anthropic", "model": "claude-sonnet-4-6" }
```

Ollama (local, any key works, for example a file containing `ollama`):

```json
"remote": { "api": "openai", "url": "http://localhost:11434/v1/chat/completions", "model": "llama3.2",
            "secret": { "source": "file", "file": "~/.config/fm-rephraser/.env-secret" } }
```

#### API key

Keychain (default):

```sh
security add-generic-password -s fm-rephraser -a llm -w <key> -T /Applications/FMRephraser.app
```

`-T` lets the app read the item without a prompt. Use `-U` to update an existing item.

Environment variable (`"source": "env"`): export the variable named by `secret.env` (default `FM_REPHRASES_LLM_SECRET`). Apps launched from Finder or Login Items do not see variables exported in `~/.zshrc`, so when the variable is missing, FMRephraser asks a login shell (`zsh -lic`) for it and caches the answer until **Reload Config**. Alternatively, make it visible to GUI apps with `launchctl setenv FM_REPHRASES_LLM_SECRET <key>` (lasts until logout).

File (`"source": "file"`): put only the key in the file and restrict it:

```sh
printf '%s' '<key>' > ~/.config/fm-rephraser/.env-secret
chmod 600 ~/.config/fm-rephraser/.env-secret
```

### Command line

`FMRephraser --rephrase "<text>"` loads the config and instructions as the menu bar app does, prints the result (or the error, with exit code 1) and exits without starting the menu bar UI:

```sh
/Applications/FMRephraser.app/Contents/MacOS/FMRephraser --rephrase "hlloo i luve ya"
```

For testing, `FMR_CONFIG_DIR` points the app (and the CLI) at another config directory instead of `~/.config/fm-rephraser`:

```sh
FMR_CONFIG_DIR=/tmp/fmr-test /Applications/FMRephraser.app/Contents/MacOS/FMRephraser --rephrase "hlloo"
```

## Limitations

- Works on plain text. Rich formatting (bold, hyperlinks with custom display text) is lost in the replaced text.
- Clipboard managers will see the intermediate copy/paste.
