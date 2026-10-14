# Manual smoke test — 14 October 2026

Host: macOS 26.5.2, Apple silicon, one built-in display. Tested the installed `/Applications/AltTabber.app` alongside the source build. This is a targeted live smoke test; broader cross-version, multi-display, and feature coverage remains open.

| Area | Live result |
|---|---|
| Settings | All 12 sidebar sections opened without a crash. Search for “large preview” returned both matching controls and navigated to the selected setting. The saved trigger was Control; changed it to the user-selected § key and confirmed the picker persisted across an app relaunch. |
| Permissions | Accessibility and Screen Recording both showed granted. Found that the two rows shared a SwiftUI identity, causing “Accessibility” to render twice. Gave each row its own identity and visually verified the corrected labels after rebuilding. |
| Automation | Installed CLI and native AppleScript `get help` responded. Live queries found 12 apps and 23 windows; Finder bundle filtering, active-window metadata and image capture worked. A stale window ID exited nonzero. CLI calls from the build sandbox failed with Apple-event error -10827; the same calls succeeded outside the sandbox. |
| Overlays | `show-switcher`, a Finder `show-preview`, and `hide-preview` returned success. The computer-use bridge bound to the standard Settings window, so it could not visually inspect the nonstandard switcher/preview panels or hold Option across multiple key presses. Shortcut routing and preview layout still need physical keyboard/visual checks. |
| Window actions | On a disposable blank TextEdit document, minimize and restore kept the same window ID and reported the correct state. Hide and unhide changed the app state but initially returned failure; an Accessibility-based path now returns success for both and was confirmed live. The blank document and TextEdit process were closed afterward. |
| Geometry | TextEdit resize/position changes arrived asynchronously through Accessibility. An immediate frame check returned `unsupported` even though the window resized shortly afterward; that check was removed. Maximize/restore and tiling still need a dedicated multi-app, visual follow-up before their result semantics can be called reliable. |
| Packaging | The built app passed `codesign --verify --deep --strict` and contains arm64 and x86_64 slices. Live testing was on arm64 only. |

Not exercised on this host: macOS 14 or Intel execution; multiple monitors, other Spaces, fullscreen and Stage Manager; Dock orientations, magnification, auto-hide and restart; Command-Tab overlay interaction; global gestures; live media, Calendar, folder bookmarks, lyrics and audio-device changes; VoiceOver; signed Sparkle feed acceptance/rejection. Most of these features are opt-in and were left at their saved settings. Automated fixtures cover several permission and empty-provider paths, but they do not replace the live checks.
