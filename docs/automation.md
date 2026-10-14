# AltTabber automation

The application bundle includes `Contents/Resources/bin/alttabber`. The source checkout also has `scripts/alttabber`, which targets `dist/AltTabber.app`. Start AltTabber before issuing commands. Queries return JSON on standard output. Invalid arguments, missing targets, unavailable permissions, and failed actions exit nonzero with an AppleScript error on standard error.

```sh
scripts/alttabber list-apps
scripts/alttabber list-windows '{"bundle":"com.apple.finder"}'
scripts/alttabber active-window
scripts/alttabber get-window '{"window":123,"image":true}'
scripts/alttabber window-action '{"window":123,"action":"left"}'
scripts/alttabber window-action '{"window":"active","action":"center"}'
scripts/alttabber show-preview '{"bundle":"com.apple.finder"}'
scripts/alttabber show-switcher '{"activeAppOnly":true}'
scripts/alttabber hide-preview
```

`window` is a CoreGraphics window ID from `list-windows`, or `"active"`. Applications with no windows appear in `list-apps` and in enabled overlays without a fabricated window ID. `pid`, `bundle`, and `app` constrain queries and target selection. `get-window` and `active-window` can include a base64 PNG with `"image":true`; this requires Screen Recording. `show-preview` accepts an optional `frame` object with `x`, `y`, `width`, and `height` in screen coordinates.

Action names are `focus`, `close`, `minimize`, `hide`, `maximize`, `fullscreen`, `quit`, `forceQuit`, `openApp`, `newWindow`, `currentSpace`, `left`, `right`, `top`, `bottom`, `topLeft`, `topRight`, `bottomLeft`, `bottomRight`, and `center`. A close action presses the application's ordinary close button, so save dialogs remain the application's responsibility. Each target is revalidated before it is acted on. `currentSpace` depends on a dynamically loaded macOS capability and reports unsupported if it is unavailable.

AppleScript uses AltTabber terminology and the same JSON arguments:

```applescript
tell application "AltTabber"
    list windows with arguments "{\"bundle\":\"com.apple.finder\"}"
    get active window
    focus window "active"
end tell
```

The dictionary also offers `show preview`, `hide preview`, `show switcher`, `list apps`, `get windows`, `get window`, `get help`, `minimize window`, `close window`, `maximize window`, `hide window`, `toggle fullscreen`, `center window`, and `position window`. `position window` takes an `action` name such as `topLeft` in its JSON arguments. The generic `perform command` remains available for every CLI command and action. The dictionary is in `Resources/AltTabber.sdef`. Install a signed build to `/Applications` for name-based AppleScript targeting. For a checkout build, target the absolute app bundle path. Automation access to Music or Spotify is requested only when their media controls are used.
