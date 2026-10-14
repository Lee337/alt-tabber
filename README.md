<div align="center">
  <img src="Resources/AppIcon.png" width="160" alt="AltTabber app icon">

  # AltTabber

  **A fast, visual window switcher for macOS.**

  Switch between the windows you actually want—not just the apps that own them.

  ![macOS 14+](https://img.shields.io/badge/macOS-14%2B-111111?style=for-the-badge&logo=apple)
  ![Universal](https://img.shields.io/badge/Apple_silicon_%2B_Intel-Universal-555555?style=for-the-badge&logo=apple)
  ![Swift 6](https://img.shields.io/badge/Swift-6-F05138?style=for-the-badge&logo=swift&logoColor=white)
  ![Version 0.5.4](https://img.shields.io/badge/version-0.5.4-007AFF?style=for-the-badge)
  [![Nightly DMG](https://github.com/Lee337/alt-tabber/actions/workflows/nightly-dmg.yml/badge.svg)](https://github.com/Lee337/alt-tabber/actions/workflows/nightly-dmg.yml)

  <br><br>

  [![Download AltTabber](https://img.shields.io/badge/Download_for_macOS-v0.5.4-007AFF?style=for-the-badge&logo=apple&logoColor=white)](https://github.com/Lee337/alt-tabber/releases/latest/download/AltTabber-v0.5.4-macOS.dmg)
</div>

---

AltTabber brings a visual, window-first workflow to **Option-Tab**. Hold **Option**, tap **Tab** to move through live previews, then release **Option** to bring the selected window forward.

No Electron or web runtime. The app is native Swift, AppKit, SwiftUI, ScreenCaptureKit, and Sparkle.

## Download

Download the disk image and install AltTabber the familiar Mac way:

### [Download AltTabber v0.5.4 for macOS](https://github.com/Lee337/alt-tabber/releases/latest/download/AltTabber-v0.5.4-macOS.dmg)

1. Open the downloaded DMG.
2. Drag **AltTabber** onto the **Applications** folder shown beside it.
3. Open AltTabber from Applications and grant Accessibility and Screen Recording access when requested.

Prefer another format? Download the [PKG installer](https://github.com/Lee337/alt-tabber/releases/latest/download/AltTabber-v0.5.4-macOS.pkg) or [portable ZIP](https://github.com/Lee337/alt-tabber/releases/latest/download/AltTabber-v0.5.4-macOS.zip).

### Nightly builds

Want the newest changes? [Download the latest nightly DMG](https://github.com/Lee337/alt-tabber/releases/download/nightly/AltTabber-nightly-macOS.dmg). GitHub automatically tests and packages a universal Apple silicon + Intel build every night from `main`. The permanent link always points to the newest successful build.

Nightlies are early builds and may be less stable than the numbered release. Each run is also retained as a downloadable [GitHub Actions artifact](https://github.com/Lee337/alt-tabber/actions/workflows/nightly-dmg.yml) for 30 days.

> [!IMPORTANT]
> This early release is ad-hoc signed and is not yet notarized by Apple. On first launch, Control-click **AltTabber** in Applications and choose **Open**. If macOS still blocks it, use **System Settings → Privacy & Security → Open Anyway**. A Developer ID-signed and notarized release is planned.

## Why AltTabber?

macOS normally switches between applications. That becomes awkward when one app has several windows—a Downloads folder, two browser windows, a project in Xcode, and a document you were editing five minutes ago.

AltTabber puts every window on equal footing:

- **Real window switching** — each open window gets its own card.
- **Live visual previews** — recognize content before reading a title.
- **Fast repeat launches** — previews are cached for ten minutes, while switched windows refresh immediately.
- **Useful titles** — see `Downloads`, document names, and active browser-window titles.
- **Multi-row grid** — scan many windows without an endless horizontal carousel.
- **Adaptive sizing** — the switcher uses more of your display and enlarges previews when fewer windows are open.
- **Native performance** — built entirely with Apple frameworks.
- **Your preferred layout** — choose a wrapping grid or horizontal strip.

## Highlights

| | Feature | What it gives you |
|---|---|---|
| 🪟 | Window-first switching | Move between individual windows instead of application groups |
| 🖼️ | Live previews | ScreenCaptureKit thumbnails captured concurrently for every eligible window |
| ⌨️ | Familiar shortcut | `⌥ Tab` forward, `⇧ ⌥ Tab` backward, release `⌥` to select |
| 🧩 | Flexible layouts | Configurable grid columns, horizontal mode, and three preview sizes |
| 🖥️ | Multi-display support | The switcher appears on the display under your pointer |
| 🚀 | Launch at Login | Keep AltTabber ready from the moment you sign in |
| 🎯 | Clickable cards | Keyboard when you want speed; pointer when you want precision |

The current source build also adds searchable settings, window actions, optional Dock previews and Command-Tab overlays, per-surface appearance, live video, gestures, folder/calendar/media widgets, AppleScript and a bundled CLI. The new surfaces and network features start disabled. The published v0.5.4 download above does not contain this source work.

The source build now includes a first, opt-in AltTabber Dock under **Settings → Custom Dock**. It can show running apps and pinned applications, files, folders, links, and separators; supports multiple profiles, app-focus profile switching, display assignment, drag reordering, icon hover previews, basic context actions, and a persistent file tray. The system Dock remains available while the replacement-Dock features are developed.

While holding **Option** in the switcher, tap **§** to toggle a large preview of the selected window. You can choose **Control** or **either key** under **Settings → Window Switcher → Shortcuts**. The preview fits the available display and fetches a higher-resolution image for the selected window. Keep holding Option and cycling to update it; releasing Option selects the window as usual. When search text is entered, **Command-P** toggles the preview instead. Change the Command key in the same settings section. If a window image cannot be captured, the preview shows the app icon and an explanation.

## Build from source

### Requirements

- macOS 14 or newer
- Xcode or the Swift 6 command-line toolchain

### Build and launch

```sh
git clone https://github.com/Lee337/alt-tabber.git
cd alt-tabber
make test
make app
make dmg
open dist/AltTabber.app
```

The generated application is available at `dist/AltTabber.app`.

> [!NOTE]
> Local builds are ad-hoc signed. For distribution outside your Mac, use an Apple Developer ID certificate, the hardened runtime, and notarization.

## Controls

| Action | Shortcut |
|---|---|
| Open and cycle forward | `⌥ Tab` |
| Cycle backward | `⇧ ⌥ Tab` |
| Switch to selected window | Release `⌥` |
| Cancel | `Esc` |
| Open without the shortcut | Menu bar → **Show Window Switcher** |

## Make it yours

Open **Settings…** from the menu-bar icon to configure:

- Grid or horizontal layout
- Two to six grid columns
- Compact, standard, or large previews
- Window-title visibility
- Launch at Login

Settings now has a searchable sidebar and opt-in controls for Dock previews, Command-Tab, gestures, widgets, online lyrics, and automatic update checks. See [automation commands](docs/automation.md) and [update signing](docs/updates.md).

The default layout is a four-column wrapping grid designed to keep a large window collection readable at a glance.

## Permissions

AltTabber asks only for the macOS permissions required by its native features:

| Permission | Used for | Without it |
|---|---|---|
| **Accessibility** | Raising and focusing the exact selected window | AltTabber can activate the app, but exact window focus may be limited |
| **Screen Recording** | Capturing live window thumbnails and richer titles | Window cards fall back to application icons |
| **Calendar** | Reading upcoming events when its widget is enabled | Calendar widget stays empty |
| **Automation** | Music and Spotify playback fallback when media controls are used | Other available media controls remain available |

Permission prompts are not repeatedly opened when access is missing. Use the menu-bar permission actions or **Settings…** to request access again.

After changing either permission, quit and reopen AltTabber so macOS refreshes the authorization state.

### If Screen Recording looks enabled but previews are missing

Local macOS privacy records can become stale after an application is rebuilt or re-signed. Remove the existing AltTabber entry from:

**System Settings → Privacy & Security → Screen & System Audio Recording**

Then add `/Applications/AltTabber.app` again, enable it, and relaunch AltTabber.

## Project structure

```text
Sources/AltTabber/
├── AppDelegate.swift              App lifecycle, menu bar, and orchestration
├── GlobalShortcutMonitor.swift    Native switcher shortcut registration
├── WindowService.swift            Combined CG, AX, and capture discovery
├── WindowQuery.swift              Shared filters, sorting, and entry identity
├── WindowActions.swift            Shared, revalidated window actions
├── DockIntegration.swift          Dock and Command-Tab observers
├── LivePreviewService.swift       Optional window video streams
├── WidgetServices.swift           Folder, calendar, and media providers
├── SwitcherPanelController.swift  Multi-display overlay positioning
├── SwitcherModel.swift            Selection and window state
├── SwitcherView.swift             SwiftUI window grid and cards
├── SettingsView.swift             Searchable settings and permissions
└── AppSettings.swift              Persistent preferences and runtime status
```

The project uses Swift Package Manager. Sparkle 2 is its updater dependency; without an AltTabber signing key and feed configured, update checks open the release page.

## Development

```sh
make build   # Debug build
make test    # Run the test suite
make app     # Create a signed release app bundle
make dmg     # Create a drag-to-Applications disk image
make installer # Create a macOS installer package in dist/
make release-artifacts # Build DMG, PKG, ZIP, and SHA-256 checksums
make run     # Build and open the app
make clean   # Remove local build output
```

If full Xcode is installed at `/Applications/Xcode.app`, the build scripts select it automatically to avoid conflicts with an older standalone Command Line Tools installation.

## Status

AltTabber is an actively evolving personal utility. Expect the core workflow to work, but treat the current releases as early builds while shortcut behavior, capture performance, and permission handling continue to mature.

Ideas, bug reports, and pull requests are welcome.

<div align="center">
  <sub>Built for people with more windows open than they care to admit.</sub>
</div>
