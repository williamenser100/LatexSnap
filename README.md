# LatexSnap

LatexSnap is a macOS menu bar app that lets you capture a region of your screen containing a math expression and converts it to raw LaTeX using Anthropic's API.

When conversion succeeds, the LaTeX is copied directly to your clipboard.

## Features

- Menu bar app with no dock icon
- Global hotkey capture: `⌘⇧⌃L`
- Click-and-drag selection overlay with live size indicator
- Screen region capture via `ScreenCaptureKit`
- OCR-to-LaTeX conversion using Anthropic Messages API
- Clipboard copy on success
- Built-in log window for debugging and status
- Secure API key storage in macOS Keychain

## Requirements

- macOS 14.0 or newer
- Xcode 15+ command line tools
- An Anthropic API key
- Permission to grant:
  - Screen Recording

## Quick Start

### 1) Clone

```bash
git clone https://github.com/williamenser100/LatexSnap.git
cd LatexSnap
```

### 2) Build and deploy

`build.sh` builds the **Debug** configuration (same as a normal Xcode build), then copies that exact app bundle to `/Applications/LatexSnap.app` with `ditto`. It **does not re-sign** the app: macOS Screen Recording (TCC) is tied to code identity, so the `/Applications` copy stays identical to the Debug product under Derived Data.

```bash
./build.sh
```

If you previously granted Screen Recording to a **different** LatexSnap build (for example after an old workflow re-signed the app), reset once and allow again for the current copy:

```bash
tccutil reset ScreenCapture com.latexsnap.app
```

### 3) Launch

Open `/Applications/LatexSnap.app`.

On first run:
- When macOS asks to allow screen capture / bypass the system picker, choose **Allow** (or enable LatexSnap under **Privacy & Security → Screen & System Audio Recording**)
- Open **Settings…** from the menu bar and paste your Anthropic API key

Optional: `setup_signing.sh` remains in the repo for older experiments but **`build.sh` does not use it**.

## How To Use

1. Press `⌘⇧⌃L`
2. Drag to select the area containing math
3. Release mouse to capture
4. Wait for conversion
5. Paste LaTeX from clipboard anywhere

If no math expression is detected, clipboard content is left unchanged.

## Menu Bar Actions

- **Capture LaTeX**: starts capture flow
- **Show Log...**: opens live log window
- **Settings...**: set or update API key
- **Quit LatexSnap**: exits app

## Development

### Build directly with Xcode

Open `LatexSnap.xcodeproj` and run the `LatexSnap` scheme.

### Build from terminal

```bash
xcodebuild \
  -project LatexSnap.xcodeproj \
  -scheme LatexSnap \
  -configuration Debug \
  build
```

The project is configured for macOS app target `LatexSnap` with deployment target `14.0`.

## Project Structure

```text
LatexSnap/
  LatexSnapApp.swift      # App entry point
  AppDelegate.swift       # Menu bar lifecycle + capture orchestration
  HotkeyManager.swift     # Global hotkey registration (⌘⇧⌃L)
  CaptureWindow.swift     # Full-screen overlay + screenshot crop flow
  SelectionView.swift     # Drag-to-select UI
  ClaudeAPIClient.swift   # Anthropic API request/response handling
  KeychainHelper.swift    # API key persistence in Keychain
  SettingsView.swift      # API key input UI
  LogManager.swift        # In-memory log store
  LogWindow.swift         # Log viewer UI
```

## Privacy and Security Notes

- Captured images are sent to Anthropic for conversion.
- API key is stored as a Keychain generic password (`com.latexsnap.app` service).
- The app does not require sandboxing in current configuration.

## Troubleshooting

- **Nothing happens on hotkey**
  - Make sure the app is running from `/Applications/LatexSnap.app`
  - Verify the hotkey is not intercepted by another app

- **Capture fails**
  - Confirm Screen Recording permission is enabled for LatexSnap in:
    - System Settings -> Privacy & Security -> Screen & System Audio Recording
  - Restart the app after changing permissions
  - If permission works for the Debug app in Derived Data but not `/Applications`, run `./build.sh` again (no re-sign) and, if needed, `tccutil reset ScreenCapture com.latexsnap.app` then re-allow

- **API errors**
  - Check key format in Settings
  - Confirm your Anthropic account and quota are active
  - Open **Show Log...** for HTTP status and error details

- **Spotlight shows two LatexSnap apps**
  - One is usually `/Applications/LatexSnap.app`; the other is the Debug product under Xcode’s Derived Data. After `./build.sh`, prefer the Applications copy; they should match the same signing profile.
