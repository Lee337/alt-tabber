# AltTabber

A small, native macOS window switcher inspired by AltTab and DockDoor. Hold **Option** and tap **Tab** to cycle through individual windows, then release Option to focus the selected window.

## Features

- Switches between individual windows instead of only applications
- Live window previews using ScreenCaptureKit
- Permission-independent global **Option-Tab** shortcut, with **Shift-Option-Tab** for reverse cycling
- Clickable window cards
- Configurable wrapping grid or horizontal-strip layouts
- Adjustable grid columns, preview sizes, and window-title visibility
- Compact landscape preview tiles with automatic keyboard-selection scrolling
- Multi-display aware overlay (it appears on the display under the pointer)
- Menu-bar controls and Launch at Login
- Native Swift/AppKit/SwiftUI implementation with no third-party dependencies
- Custom layered-window app icon with complete macOS Retina assets

## Requirements

- macOS 14 or newer
- Swift 6 / Xcode Command Line Tools
- Accessibility permission for focusing a specific window (the Option-Tab shortcut itself does not require it)
- Screen Recording permission for live previews (the switcher still works with app icons without it)

## Build and run

```sh
make test
make app
open dist/AltTabber.app
```

On first launch, approve **Accessibility** when macOS asks. Use the menu-bar window icon to request Accessibility or Screen Recording access again. Permission changes may require restarting AltTabber.

Automatic Accessibility and Screen Recording prompts are shown at most once. If access is later revoked, AltTabber reports the missing permission without repeatedly opening a macOS prompt; use **Settings…** or the menu-bar permission actions to request it again.

The menu-bar menu and Settings window show the current Option-Tab shortcut status. AltTabber automatically retries the shortcut listener after Accessibility access is granted, so a restart normally is not required for that permission.

Choose **Settings…** from the menu-bar icon to customize the switcher. The default is a four-column wrapping grid; the original horizontal strip remains available as an option.

The generated app is ad-hoc signed and intended for local use. A distributable release should use an Apple Developer ID certificate, hardened runtime, and notarization.

If full Xcode is installed at `/Applications/Xcode.app`, the build scripts select it automatically. This avoids failures when an older Command Line Tools installation is still active.

## Controls

| Action | Shortcut |
| --- | --- |
| Cycle forward | Option-Tab |
| Cycle backward | Shift-Option-Tab |
| Select | Release Option |
| Cancel | Escape |

## Project layout

- `WindowService.swift`: discovers, captures, and focuses macOS windows
- `GlobalShortcutMonitor.swift`: registers Option-Tab with macOS and tracks Option release
- `SwitcherPanelController.swift`: manages the non-activating overlay
- `SwitcherView.swift`: renders preview cards in SwiftUI
- `scripts/build-app.sh`: creates a local `.app` bundle
