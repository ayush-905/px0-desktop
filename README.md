# px0 Desktop

A native macOS app for [px0](https://px0.ai): px0 in its own windows and tabs
instead of a browser tab. It's a small Swift/AppKit wrapper around the system
WebView. It doesn't bundle Chromium and doesn't change px0.

Unofficial. px0 is by Arpit Bhayani (MIT).

## What it does

- **One native tab per folder or pull request.** Each tab runs its own px0. Tabs come back when you relaunch.
- **Start page** with Open Folder, Open Pull Request and your recent items.
- **px0's own shortcuts work.** In a browser, ⌘W closes the whole browser tab. Here, ⌘W closes the file tab inside px0, as in an editor, and ⇧⌘W closes the px0 tab. ⌘P, ⌘K and px0's other shortcuts work as usual.
- **External links** (GitHub, docs) open in your default browser.
- **Unsaved edits are protected.** Closing a tab or quitting asks first while px0 has unsaved changes or a coding agent is still writing.
- **Your shell environment.** px0 gets the PATH from your login shell, so it finds git, gh, language servers and coding agents even when you start the app from the Dock.
- **Nothing left running.** Each px0 stops when its tab closes or the app quits, even if the app crashes.

## Requirements

- macOS 12 or later, and the Xcode Command Line Tools (`xcode-select --install`)
- px0 on your PATH:

```bash
curl -fsSL https://px0.ai/install.sh | sh
```

## Build and install

```bash
./build.sh
```

That builds `build/px0 Desktop.app` for both Apple Silicon and Intel. To build it
and copy it to /Applications:

```bash
./build.sh install
```

## Sharing it

The app runs on Apple Silicon and Intel Macs (macOS 12 or later). Everyone
installs px0 themselves. Themes and px0's font settings are per person, chosen in
px0's theme picker and settings (⌘,).

- **Simplest:** share this repository. Each person runs `./build.sh install`, which
  needs the Xcode Command Line Tools. An app you build yourself isn't flagged by
  macOS as a download.
- **Sending the built app instead** (zip, Slack): it's signed for local use only,
  so macOS blocks it the first time it opens. The person allows it in System
  Settings → Privacy & Security → **Open Anyway**. To avoid that, sign it with an
  Apple Developer ID and notarize it.
- **Publishing it publicly:** Cursor Dark's colors come from Cursor's app files.
  For a public release, consider shipping only Cursor Dark Modern, whose colors
  come from VS Code (MIT).

## Opening things from a terminal

```bash
open -a "px0 Desktop" .
```

```bash
open -a "px0 Desktop" https://github.com/owner/repo/pull/123
```

A shell alias makes this shorter: `alias px0d='open -a "px0 Desktop"'`.
You can also drop a folder on the window or on the Dock icon.

## Shortcuts

| Keys | Action |
| --- | --- |
| ⌘T / ⌘N | New tab / new window |
| ⌘O | Open folder |
| ⌥⌘O | Open pull request (fills in a PR URL from the clipboard) |
| ⇧⌘W | Close the px0 tab (⌘W closes px0's file tab) |
| ⌥⌘W | Close the window |
| ⇧⌘] / ⇧⌘[ | Next / previous tab (px0 uses ⌃Tab for its own tabs) |
| ⌘R | Reload the page |
| ⌘= / ⌘- / ⌘0 | Zoom in / out / actual size (applies to every tab) |
| ⌘[ / ⌘] | Back / forward |

When px0 and the app both use a shortcut, px0 gets it first.

## Themes

The app adds two themes to px0's theme picker (⌘K, then search "theme"):

- **Cursor Dark Modern**: "Default Dark Modern", the theme Cursor is set to. It uses
  VS Code's `dark_modern` → `dark_plus` → `dark_vs` files plus the editor's built-in
  dark defaults.
- **Cursor Dark**: Cursor's own default dark theme.

The colors come from the theme files inside Cursor.app, not from screenshots. Each px0
syntax color is the color Cursor's rules give that kind of token. A small script also
colors control-flow keywords (`if`, `return`, `import`) apart from declarations
(`const`, `func`), as Cursor does; px0 itself marks every keyword the same way.

A theme can't match everything:

- px0's highlighter labels fewer kinds of token than Cursor does. Things Cursor
  works out from your language server, like type names in declarations and struct
  fields, show in the plain text color.
- Layout and font sizes in px0's own UI (tabs, explorer, status bar) stay px0's.
- Fonts aren't part of a px0 theme. To match Cursor's default editor font, set
  px0's settings (⌘,) to Menlo, size 12, line height 18.

To add another theme, put a CSS file in `Themes/` in the same format as px0's
`web/themes/*.css`, then run `./build.sh` again.

## How it works

- Each tab runs `px0 -no-open -no-color -port 0 <folder or PR URL>`, reads the `url:` line px0 prints, and shows that page in a WKWebView.
- px0 runs under a small `sh` helper that also holds one end of a pipe from the app. When the pipe closes (tab closed, app quit, or app crashed), the helper sends px0 SIGTERM, and px0 shuts down its language servers too.
- If a recent folder is a clone of a pull request's repository, px0 starts there and checks the PR out as a git worktree instead of cloning it again.
- When you open a pull request from px0's command palette, it opens in a new tab instead of your browser.
- px0 still updates itself the way it always does. Tabs keep running the old version until you reopen them or relaunch the app.

## Settings

Use a specific px0 binary instead of the first one on your PATH:

```bash
defaults write local.px0.desktop Px0Path /path/to/px0
```

## Troubleshooting

- **Help ▸ Show px0 Log** opens `~/Library/Logs/px0-desktop.log`, which has the output from every px0 the app ran. The log starts fresh at each launch.
- Right-click a page and choose **Inspect Element** for WebKit's web inspector.
- `"build/px0 Desktop.app/Contents/MacOS/px0-desktop" --debug-snapshot shot.png` saves a picture of each page as it finishes loading.
